import { useState, useRef } from 'react';
import Terminal from './components/Terminal';
import ActionBar from './components/ActionBar';
import Mesa from './components/Mesa';
import ManoRival from './components/ManoRival';
import MiMano from './components/MiMano';
import './App.css';

export default function App() {
  const [jugador, setJugador] = useState('jugador1');
  const [conectado, setConectado] = useState(false);
  const [misCartas, setMisCartas] = useState([]);
  const [cantRival, setCantRival] = useState(3);
  const [cartasMesa, setCartasMesa] = useState([]);
  const [bazaWinners, setBazaWinners] = useState([]);
  const [pts, setPts] = useState({ jugador1:0, jugador2:0 });
  const [mano, setMano] = useState('');
  const [miTurno, setMiTurno] = useState(false);
  const [tipoTurno, setTipoTurno] = useState('');
  const [opciones, setOpciones] = useState([]);
  const [eventos, setEventos] = useState([]);
  const [terminada, setTerminada] = useState(false);
  const [resultado, setResultado] = useState('');
  const [conectando, setConectando] = useState(false);
  const [termAbierto, setTermAbierto] = useState(true);
  const [jugandoCarta, setJugandoCarta] = useState(null);
  const ws = useRef(null);

  function log(texto, tipo='info') {
    setEventos(p => [...p, {texto, tipo}]);
  }

  function parseCartas(str) {
    try {
      const s = str.replace(/[\[\]]/g,'').trim();
      if (!s) return [];
      const partes = s.split('),');
      return partes.map((p,i) => i<partes.length-1 ? p+')' : p).map(p=>p.trim());
    } catch { return [str]; }
  }

  function parseOpciones(ev) {
    const m = ev.match(/\[(.+?)\]/);
    if (m) return m[1].split(',').map(s => s.trim());
    return [];
  }

  function limpiarTurno() {
    setMiTurno(false);
    setTipoTurno('');
    setOpciones([]);
  }

  function conectar() {
    if (conectando) return;
    setConectando(true);
    limpiarTurno();
    setCartasMesa([]);
    setEventos([]);
    log('Transmitiendo seña...', 'conexion');

    const w = new WebSocket('ws://localhost:8080/ws');
    ws.current = w;

    w.onopen = () => {
      setConectado(true);
      setConectando(false);
      log(`${jugador} reporta servicio`, 'conexion');
      w.send(JSON.stringify({jugador}));
    };

    w.onmessage = e => {
      let d;
      try { d = JSON.parse(e.data); } catch { return; }

      if (d.tipo === 'cartas') {
        const cs = parseCartas(d.cartas);
        setMisCartas(cs);
        log('Munición recibida', 'cartas');
        return;
      }

      if (d.tipo === 'evento') evHandler(d.mensaje);
    };

    w.onclose = () => {
      setConectado(false); setConectando(false); limpiarTurno();
      log('Comunicaciones caídas', 'error');
    };

    w.onerror = () => {
      setConectando(false);
      log('Error. ¿El cuartel está activo?', 'error');
    };
  }

  function evHandler(raw) {
    const ev = raw.replace(/^['"]|['"]$/g,'');

    if (ev === 'inicio_partida') {
      setTerminada(false); setCartasMesa([]); setMisCartas([]); setCantRival(3);
      setBazaWinners([]);
      limpiarTurno();
      log('OPERACIÓN INICIADA', 'titulo');
      return;
    }

    if (ev.startsWith('partida_terminada')) {
      const m = ev.match(/partida_terminada\((\w+),(\d+),(\d+)\)/);
      if (m) {
        setTerminada(true);
        setResultado(`Victoria de ${m[1]} — ${m[2]} a ${m[3]}`);
        log(`${m[1]} vence ${m[2]} a ${m[3]}`, 'titulo');
      }
      return;
    }

    if (ev.startsWith('estado_mano')) {
      const m = ev.match(/estado_mano\((\w+),(\d+),(\d+)\)/);
      if (m) {
        setPts({jugador1:+m[2],jugador2:+m[3]});
        setMano(m[1]);
        setCantRival(3);
        log(`${m[2]} - ${m[3]} | Mano: ${m[1]}`, 'puntaje');
      }
      return;
    }

    if (ev.startsWith('carta_jugada')) {
      const m = ev.match(/carta_jugada\((\w+),(carta\(\d+,\s*\w+\))\)/);
      if (m) {
        setCartasMesa(p => [...p, {jugador:m[1], carta:m[2]}]);
        if (m[1] === jugador) {
          setJugandoCarta(m[2]);
          setTimeout(() => {
            setMisCartas(p => p.filter(c => c !== m[2]));
            setJugandoCarta(null);
          }, 350);
        } else {
          setCantRival(p => Math.max(0, p-1));
        }
        log(`${m[1]} despliega ${m[2]}`, 'accion');
      }
      return;
    }

    if (ev.startsWith('ganador_baza')) {
      const m = ev.match(/ganador_baza\((\w+)\)/);
      if (m) {
        setBazaWinners(p => [...p, m[1]]);
        log(`Baza para ${m[1]}`, 'resultado');
      }
      return;
    }

    if (ev.startsWith('ganador_mano')) {
      const m = ev.match(/ganador_mano\((\w+),(\d+)\)/);
      if (m) {
        setCartasMesa([]);
        setBazaWinners([]);
        log(`Mano: ${m[1]} — ${m[2]} pts`, 'resultado');
      }
      return;
    }

    const turnMap = {
      turno_carta:    'Turno: Jugar carta',
      turno_apuesta:  'Turno: Apuesta',
      turno_retruco:  'Turno: Retruco',
      turno_vale4:    'Turno: Vale 4',
      responder_truco: 'Turno: Responder truco',
      responder_retruco:'Turno: Responder retruco',
      responder_vale4: 'Turno: Responder vale 4',
    };

    for (const [pat, lbl] of Object.entries(turnMap)) {
      if (ev.startsWith(pat) && ev.includes(jugador)) {
        setMiTurno(true);
        setTipoTurno(pat);
        let opts = parseOpciones(ev);
        if (pat === 'turno_vale4' && opts.length === 0) opts = ['vale4','nada'];
        setOpciones(opts);
        log(lbl, 'turno');
        return;
      }
    }

    const labels = {
      canto_truco:    (_,j) => `${j} canta TRUCO`,
      canto_retruco:  (_,j) => `${j} canta RETRUCO`,
      canto_vale4:    (_,j) => `${j} canta VALE 4`,
      acepto_truco:   (_,j) => `${j} acepta el truco`,
      no_quiero:      (_,j) => `${j} se rinde`,
    };
    for (const [k,fn] of Object.entries(labels)) {
      if (ev.startsWith(k)) {
        const m = ev.match(new RegExp(`${k}\\((\\w+)\\)`));
        if (m) log(fn(k,m[1]), 'accion');
        return;
      }
    }

    if (ev.startsWith('estado_apuesta')) {
      const m = ev.match(/estado_apuesta\((.+)\)/);
      if (m) log(`Apuesta: ${m[1]}`, 'info');
      return;
    }

    log(`[${ev}]`, 'info');
  }

  function enviar(val) {
    if (!ws.current || !miTurno) return;
    const n = Number(val);
    ws.current.send(JSON.stringify({accion: Number.isInteger(n)&&val!=='' ? n : val}));
    log(`→ ${val}`, 'envio');
    limpiarTurno();
  }

  function reiniciar() {
    setTerminada(false); setResultado('');
    setMisCartas([]); setCantRival(3);
    setCartasMesa([]); setBazaWinners([]);
    setPts({jugador1:0,jugador2:0});
    setMano(''); setEventos([]); limpiarTurno();
    if (ws.current) { ws.current.close(); ws.current = null; }
    setConectado(false);
  }

  return (
    <div className="app">
      <div className="bar">
        <span className="insignia">★</span>
        <h1>TRUCO</h1>
        <span className="insignia">★</span>
        <div className="bar-pts">
          <span className={`bpts-item ${jugador==='jugador1'?'yo':''}`}>{pts.jugador1}</span>
          <span className="bpts-div">:</span>
          <span className={`bpts-item ${jugador==='jugador2'?'yo':''}`}>{pts.jugador2}</span>
          <span className="bpts-mano">{mano||'—'}</span>
        </div>
        <input value={jugador} onChange={e=>setJugador(e.target.value)}
          disabled={conectado} placeholder="Nombre" />
        <button onClick={conectar} disabled={conectado||conectando}
          className={conectado?'ok':''}>
          {conectando ? '...' : conectado ? '✓ En servicio' : 'Conectar'}
        </button>
        <span className={`status ${conectado?'ok':'err'}`}>
          {conectado ? `● ${jugador}` : '○ Desconectado'}
        </span>
      </div>

      <div className="body">
        <button className={`toggle-term ${termAbierto?'':'cerrado'}`}
          onClick={() => setTermAbierto(o => !o)} title={termAbierto?'Ocultar bitácora':'Abrir bitácora'}>
          <span>{termAbierto ? '◀' : '▶'}</span>
          {termAbierto && <span className="tgl-label">BITÁCORA</span>}
        </button>

        <div className={`left-col ${termAbierto?'':'cerrado'}`}>
          <div className="term-header">BITÁCORA DE GUERRA</div>
          <Terminal eventos={eventos} />
        </div>

        <div className="panel-tab">
          <div className="sec rival"><h3>◇ FRENTE ENEMIGO</h3><ManoRival cantidad={cantRival}/></div>
          <div className="sec mesa-sec"><h3>◇ CAMPO DE BATALLA</h3><Mesa cartasJugadas={cartasMesa} bazaWinners={bazaWinners} jugador={jugador}/></div>
          <div className="sec mis-cartas-sec"><h3>◇ MI DOTACIÓN</h3>
            <MiMano cartas={misCartas} onCartaClick={tipoTurno==='turno_carta' ? enviar : null} jugandoCarta={jugandoCarta} />
          </div>
        </div>
      </div>

      <ActionBar
        opciones={opciones}
        miTurno={miTurno}
        tipoTurno={tipoTurno}
        onAction={enviar}
        conectado={conectado}
      />

      {terminada && (
        <div className="overlay" onClick={reiniciar}>
          <div className="overlay-box">
            <h2>MISIÓN CUMPLIDA</h2>
            <p>{resultado}</p>
            <small>Toque para replegarse</small>
          </div>
        </div>
      )}
    </div>
  );
}
