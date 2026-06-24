import { useRef, useEffect } from 'react';

export default function Terminal({ eventos }) {
  const logRef = useRef(null);

  useEffect(() => {
    if (logRef.current)
      logRef.current.scrollTop = logRef.current.scrollHeight;
  }, [eventos]);

  return (
    <div className="terminal-log" ref={logRef}>
      {eventos.length === 0 && (
        <div className="tl info">Esperando órdenes del cuartel...</div>
      )}
      {eventos.map((ev, i) => (
        <div key={i} className={`tl ${ev.tipo}`}>{ev.texto}</div>
      ))}
    </div>
  );
}
