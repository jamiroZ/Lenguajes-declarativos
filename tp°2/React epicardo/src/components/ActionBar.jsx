export default function ActionBar({ opciones, miTurno, tipoTurno, onAction, conectado }) {
  const esTurnoCarta = tipoTurno === 'turno_carta';

  if (!conectado) return null;

  if (miTurno && opciones.length > 0 && !esTurnoCarta) {
    return (
      <div className="action-bar">
        <div className="action-buttons">
          {opciones.map((opt, i) => (
            <button key={i} className="action-btn" onClick={() => onAction(opt)}>
              {opt}
            </button>
          ))}
        </div>
      </div>
    );
  }

  return (
    <div className="action-bar">
      <span className="action-idle">Esperando órdenes...</span>
    </div>
  );
}
