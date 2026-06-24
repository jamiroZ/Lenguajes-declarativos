import { useState, useRef } from 'react';
import Terminal from './components/Terminal';
import ActionBar from './components/ActionBar';
import Mesa from './components/Mesa';
import ManoRival from './components/ManoRival';
import MiMano from './components/MiMano';
import usePrologGame from './hooks/usePrologGame';
import './App.css';

export default function App() {
  const [jugador, setJugador] = useState('jugador1');
  const [termAbierto, setTermAbierto] = useState(true);
  const [jugandoCarta, setJugandoCarta] = useState(null);

  const { estado, conectar, enviar, reiniciar } = usePrologGame();

  const {
    conectado, conectando, misCartas, cantRival,
    cartasMesa, bazaWinners, pts, mano, miTurno,
    tipoTurno, opciones, eventos, terminada, resultado,
  } = estado;

  function handleCardClick(idx) {
    if (!miTurno || (tipoTurno !== 'turno_carta' && tipoTurno !== 'turno_vale4')) return;
    const carta = misCartas[idx - 1];
    if (!carta) return;
    setJugandoCarta(carta);
    setTimeout(() => setJugandoCarta(null), 350);
    enviar(String(idx));
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
        <button onClick={()=>conectar(jugador)} disabled={conectado||conectando}
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
            <MiMano cartas={misCartas} onCartaClick={tipoTurno==='turno_carta'||tipoTurno==='turno_vale4' ? handleCardClick : null} jugandoCarta={jugandoCarta} />
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
