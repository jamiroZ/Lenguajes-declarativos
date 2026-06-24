import { useState, useEffect, useRef, useCallback } from 'react';
import SWIPL from 'swipl-wasm';

const HOST = import.meta.env.VITE_SERVER_HOST || window.location.hostname;
const SERVER_URL = `ws://${HOST}:8080/ws`;

const ESTADO_INICIAL = {
  jugador: 'jugador1',
  conectado: false,
  conectando: false,
  cargando: true,
  misCartas: [],
  cantRival: 3,
  cartasMesa: [],
  bazaWinners: [],
  pts: { jugador1: 0, jugador2: 0 },
  mano: '',
  miTurno: false,
  tipoTurno: '',
  opciones: [],
  eventos: [],
  terminada: false,
  resultado: '',
  termAbierto: true,
};

function prologToJs(v) {
  if (v === null || v === undefined) return v;
  if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') return v;
  if (typeof v === 'object') {
    if (v.$t === 's') return v.v;
    if (v.$t === 'i') return Number(v.v);
    if (v.$t === 'r') return Number(v.v);
    if (v.$t === 'v') return undefined;
  }
  return v;
}

function sanitizar(v) {
  v = prologToJs(v);
  if (v === null || v === undefined) return v;
  if (typeof v === 'string' || typeof v === 'number' || typeof v === 'boolean') return v;
  if (Array.isArray(v)) return v.map(sanitizar);
  if (typeof v === 'object') {
    if (v.$t) {
      if (v.$t === 'dict') {
        const out = {};
        for (const [k, val] of Object.entries(v)) {
          if (k === '$t') continue;
          const s = sanitizar(val);
          if (s !== undefined) out[k] = s;
        }
        return Object.keys(out).length ? out : undefined;
      }
      const keys = Object.keys(v).filter(k => k !== '$t');
      if (keys.length > 0 && keys.every(k => /^\d+$/.test(k))) {
        const args = keys.sort((a, b) => Number(a) - Number(b)).map(k => sanitizar(v[k]));
        return `${v.$t}(${args.join(',')})`;
      }
      return undefined;
    }
    const out = {};
    for (const [k, val] of Object.entries(v)) {
      const s = sanitizar(val);
      if (s !== undefined) out[k] = s;
    }
    return Object.keys(out).length ? out : undefined;
  }
  return String(v);
}

function prologCartasToList(lista) {
  if (!Array.isArray(lista)) return [];
  return lista.map(c => sanitizar(c)).filter(Boolean);
}

export default function usePrologGame() {
  const [estado, setEstado] = useState(ESTADO_INICIAL);
  const prologRef = useRef(null);
  const wsRef = useRef(null);
  const pendienteRef = useRef(null);

  // Inicializar SWI-Wasm
  useEffect(() => {
    let cancelado = false;
    (async () => {
      if (prologRef.current) return;
      try {
        console.log('[Prolog] Iniciando SWI-Wasm...');
        const swipl = await SWIPL({
          arguments: ['-q'],
          locateFile: (path) => `/swipl/${path}`,
        });
        if (cancelado || prologRef.current) return;

        const prolog = swipl.prolog;
        const resp = await fetch('/cliente_wasm.pl');
        const codigo = await resp.text();
        await prolog.load_string(codigo);
        if (cancelado || prologRef.current) return;

        prolog.query('inicializar').once();
        prologRef.current = prolog;
        console.log('[Prolog] SWI-Wasm listo');

        // Si hay una conexión pendiente, ejecutarla ahora
        if (pendienteRef.current) {
          console.log('[Prolog] Conectando pendiente:', pendienteRef.current);
          conectarAhora(pendienteRef.current);
          pendienteRef.current = null;
        }

        setEstado(s => ({ ...s, cargando: false }));
      } catch (e) {
        console.error('[Prolog] Error cargando SWI-Wasm:', e);
        if (!cancelado) setEstado(s => ({ ...s, cargando: false }));
      }
    })();

    return () => {
      cancelado = true;
      if (wsRef.current) wsRef.current.close();
    };
  }, []);

  function plCall(goal) {
    const pl = prologRef.current;
    if (!pl) { console.warn('[Prolog] plCall sin engine:', goal); return; }
    console.log('[Prolog] plCall:', goal);
    try { pl.query(goal).once(); } catch (e) { console.error('[Prolog] plCall error:', e, goal); }
  }

  function flushAcciones() {
    const ws = wsRef.current;
    const pl = prologRef.current;
    if (!ws || !pl || ws.readyState !== WebSocket.OPEN) { console.warn('[Prolog] flushAcciones: WS no abierto'); return; }
    let sent = 0;
    let safety = 100;
    while (safety--) {
      const r = pl.query('siguiente_envio(JSON)').once();
      if (!r || !r.JSON) break;
      const payload = prologToJs(r.JSON);
      console.log('[Prolog] Enviando:', payload);
      ws.send(payload);
      sent++;
    }
    if (sent === 0) console.log('[Prolog] flushAcciones: nada que enviar');
  }

  function syncEstado() {
    const pl = prologRef.current;
    if (!pl) return { ...ESTADO_INICIAL, cargando: false };
    const r = pl.query('obtener_estado(E)').once();
    if (!r || !r.E) {
      console.warn('[Prolog] syncEstado: obtener_estado falló');
      return { ...ESTADO_INICIAL, cargando: false };
    }

    const rawKeys = Object.keys(r.E);
    const rawTypes = {};
    rawKeys.forEach(k => { rawTypes[k] = typeof r.E[k]; });
    console.log('[Prolog] syncEstado raw keys:', JSON.stringify(rawKeys), 'types:', JSON.stringify(rawTypes));

    const e = sanitizar(r.E) || {};
    console.log('[Prolog] syncEstado sanit keys:', Object.keys(e), 'conectado:', e.conectado, 'misCartas:', e.misCartas?.length, 'eventos:', e.eventos?.length);
    return {
      jugador: e.jugador || '',
      conectado: e.conectado === 'true' || e.conectado === true,
      conectando: false,
      cargando: false,
      misCartas: prologCartasToList(e.misCartas),
      cantRival: 3,
      cartasMesa: Array.isArray(e.cartasMesa) ? e.cartasMesa : [],
      bazaWinners: Array.isArray(e.bazaWinners) ? e.bazaWinners : [],
      pts: {
        jugador1: (e.pts && e.pts.jugador1) || 0,
        jugador2: (e.pts && e.pts.jugador2) || 0,
      },
      mano: e.mano || '',
      miTurno: e.miTurno === 'true' || e.miTurno === true,
      tipoTurno: e.tipoTurno || '',
      opciones: Array.isArray(e.opciones) ? e.opciones : [],
      eventos: Array.isArray(e.eventos) ? e.eventos : [],
      terminada: e.terminada === 'true' || e.terminada === true,
      resultado: e.resultado || '',
      termAbierto: true,
    };
  }

  function actualizar() {
    setEstado(syncEstado());
  }

  function conectarAhora(jugador) {
    if (wsRef.current) { console.log('[Prolog] conectarAhora: WS ya existe'); return; }

    console.log('[Prolog] Creando WS a', SERVER_URL);
    const ws = new WebSocket(SERVER_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      console.log('[Prolog] WS abierto, registrando como', jugador);
      plCall(`conectar(${jugador})`);
      flushAcciones();
      actualizar();
    };

    ws.onmessage = (e) => {
      console.log('[Prolog] WS mensaje recibido:', e.data);
      let d;
      try { d = JSON.parse(e.data); } catch { console.warn('[Prolog] WS mensaje no JSON:', e.data); return; }
      const pl = prologRef.current;
      if (!pl) { console.warn('[Prolog] WS mensaje pero sin engine'); return; }

      if (d.tipo === 'cartas') {
        plCall(`procesar_mensaje_ws('cartas(${d.cartas})')`);
      } else if (d.tipo === 'evento') {
        plCall(`procesar_mensaje_ws('evento(${d.mensaje})')`);
      } else {
        console.warn('[Prolog] WS tipo desconocido:', d.tipo);
      }
      flushAcciones();
      actualizar();
    };

    ws.onclose = () => {
      console.log('[Prolog] WS cerrado');
      wsRef.current = null;
      setEstado(s => ({ ...s, conectado: false, conectando: false }));
    };

    ws.onerror = (err) => {
      console.error('[Prolog] WS error:', err);
      wsRef.current = null;
      setEstado(s => ({ ...s, conectado: false, conectando: false }));
    };
  }

  const conectar = useCallback((jugador) => {
    if (wsRef.current) { console.log('[Prolog] conectar: ya conectado'); return; }

    if (!prologRef.current) {
      console.log('[Prolog] conectar: engine no listo, encolando', jugador);
      pendienteRef.current = jugador;
      setEstado(s => ({ ...s, conectando: true }));
      return;
    }

    console.log('[Prolog] conectar:', jugador);
    setEstado(s => ({ ...s, conectando: true }));
    conectarAhora(jugador);
  }, []);

  const enviar = useCallback((val) => {
    const pl = prologRef.current;
    if (!pl) return;
    const n = Number(val);
    if (Number.isInteger(n) && val !== '') {
      plCall(`encolar_accion(${n})`);
    } else {
      plCall(`encolar_accion('${val}')`);
    }
    flushAcciones();
    actualizar();
  }, []);

  const reiniciar = useCallback(() => {
    if (wsRef.current) { wsRef.current.close(); wsRef.current = null; }
    if (prologRef.current) plCall('inicializar');
    actualizar();
  }, []);

  return { estado, conectar, enviar, reiniciar };
}
