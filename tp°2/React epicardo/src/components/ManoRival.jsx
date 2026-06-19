import Card from './Card';

export default function ManoRival({ cantidad }) {
  return (
    <div className="mano-rival">
      {Array.from({length: cantidad}).map((_, i) => (
        <Card key={i} src="/Deck/back.png" alt="dorso" />
      ))}
    </div>
  );
}
