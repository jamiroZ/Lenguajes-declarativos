import Card from './Card';

const idxMap = {1:1,2:2,3:3,4:4,5:5,6:6,7:7,10:8,11:9,12:10};

function cartaASrc(carta) {
  const m = carta.match(/carta\((\d+),\s*(\w+)\)/);
  if (!m) return '/Deck/back.png';
  return `/Deck/${m[2]}/${idxMap[m[1]]}_${m[2]}.png`;
}

export default function Mesa({ cartasJugadas, bazaWinners, jugador }) {
  const bazas = [];
  for (let i = 0; i < cartasJugadas.length; i += 2) {
    bazas.push(cartasJugadas.slice(i, i + 2));
  }

  const mostradas = bazas.slice(0, 3);
  const vacias = 3 - mostradas.length;

  function cellCont(cartas, player, isRival) {
    const carta = cartas.find(c => c.jugador === player);
    if (!carta) return null;
    const bi = cartasJugadas.indexOf(carta);
    const bazaIdx = Math.floor(bi / 2);
    const ganador = bazaWinners[bazaIdx];
    const perdio = ganador && ganador !== carta.jugador;
    const cls = `${perdio ? 'perdedor' : ''} ${isRival ? 'cj-dorso' : ''} anim-card`.trim();
    return (
      <div className={isRival ? 'anim-rival-wrap' : 'anim-player-wrap'}>
        <Card src={cartaASrc(carta.carta)} alt={carta.carta} className={cls} />
      </div>
    );
  }

  return (
    <div className="mesa-grid">
      <div className="mg-row">
        <span className="mg-row-label" />
        <span className="mg-col-label">Ronda 1</span>
        <span className="mg-col-label">Ronda 2</span>
        <span className="mg-col-label">Ronda 3</span>
      </div>
      <div className="mg-row">
        <span className="mg-row-label">Rival</span>
        {mostradas.map((b, i) => {
          const rival = b.find(c => c.jugador !== jugador)?.jugador || '';
          return <div key={`r${i}`} className="mg-cell">{cellCont(b, rival, true)}</div>;
        })}
        {Array.from({length: vacias}, (_, i) => <div key={`er${i}`} className="mg-cell" />)}
      </div>
      <div className="mg-row">
        <span className="mg-row-label">Yo</span>
        {mostradas.map((b, i) => {
          const yo = b.find(c => c.jugador === jugador)?.jugador || jugador;
          return <div key={`y${i}`} className="mg-cell">{cellCont(b, jugador, false)}</div>;
        })}
        {Array.from({length: vacias}, (_, i) => <div key={`ey${i}`} className="mg-cell" />)}
      </div>
    </div>
  );
}
