export default function Card({ src, alt, className, onClick, clickeable }) {
  return (
    <div
      className={`carta ${className||''} ${clickeable?'clickeable':''}`}
      onClick={clickeable ? onClick : undefined}
    >
      <img src={src} alt={alt||'carta'} draggable={false} />
    </div>
  );
}
