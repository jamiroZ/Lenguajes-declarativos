import Card from './Card';

const idxMap = {1:1,2:2,3:3,4:4,5:5,6:6,7:7,10:8,11:9,12:10};

function cartaASrc(carta) {
  const m = carta.match(/carta\((\d+),\s*(\w+)\)/);
  if (!m) return '/Deck/back.png';
  return `/Deck/${m[2]}/${idxMap[m[1]]}_${m[2]}.png`;
}

export default function MiMano({ cartas, onCartaClick, jugandoCarta }) {
  if (!cartas.length) return <div className="mi-mano vacia">Esperando cartas...</div>;
  return (
    <div className="mi-mano">
      {cartas.map((c, i) => (
        <Card
          key={i}
          src={cartaASrc(c)}
          alt={c}
          clickeable={!!onCartaClick}
          onClick={() => onCartaClick && onCartaClick(i+1)}
          className={c === jugandoCarta ? 'usando' : ''}
        />
      ))}
    </div>
  );
}
