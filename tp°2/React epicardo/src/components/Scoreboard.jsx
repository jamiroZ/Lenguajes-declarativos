export default function Scoreboard({ puntajes, manoActual, jugador }) {
  return (
    <div className="scoreboard">
      <div className={`sb-item ${jugador==='jugador1'?'yo':''}`}>
        <span className="sb-nombre">Jugador 1</span>
        <span className="sb-pts">{puntajes.jugador1??0}</span>
      </div>
      <div className="sb-mano">
        <span>Mano: {manoActual||'—'}</span>
      </div>
      <div className={`sb-item ${jugador==='jugador2'?'yo':''}`}>
        <span className="sb-pts">{puntajes.jugador2??0}</span>
        <span className="sb-nombre">Jugador 2</span>
      </div>
    </div>
  );
}
