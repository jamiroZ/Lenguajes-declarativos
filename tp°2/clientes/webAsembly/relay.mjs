import { WebSocketServer } from 'ws';

const PORT = process.env.PORT || 9090;
const wss = new WebSocketServer({ port: PORT });

console.log(`Relay en puerto ${PORT}`);

let waitingPlayer = null;

wss.on('connection', (ws) => {
  console.log('Nuevo cliente');

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); } catch { return; }

    if (msg.tipo === 'registro') {
      ws.jugador = msg.jugador;
      ws.send(JSON.stringify({ tipo: 'registro_ok', jugador: msg.jugador }));
      console.log(`Registrado: ${msg.jugador}`);
      emparejar(ws);
      return;
    }

    // Reenviar al otro jugador
    if (ws.rival && ws.rival.readyState === 1) {
      ws.rival.send(raw);
    }
  });

  ws.on('close', () => {
    console.log('Cliente desconectado');
    if (ws.rival) {
      ws.rival.rival = null;
      ws.rival.send(JSON.stringify({ tipo: 'rival_desconectado' }));
    }
  });
});

function emparejar(ws) {
  if (waitingPlayer) {
    const rival = waitingPlayer;
    waitingPlayer = null;
    ws.rival = rival;
    rival.rival = ws;

    // Asignar roles: el primero que llegó es jugador1
    const j1 = rival;
    const j2 = ws;

    j1.rol = 'jugador1';
    j2.rol = 'jugador2';

    j1.send(JSON.stringify({ tipo: 'emparejado', rival: j2.jugador || 'jugador2', rol: 'jugador1', turno: true }));
    j2.send(JSON.stringify({ tipo: 'emparejado', rival: j1.jugador || 'jugador1', rol: 'jugador2', turno: false }));

    console.log(`Emparejados: ${j1.rol} (${j1.jugador}) <-> ${j2.rol} (${j2.jugador})`);
  } else {
    waitingPlayer = ws;
    ws.send(JSON.stringify({ tipo: 'esperando' }));
  }
}
