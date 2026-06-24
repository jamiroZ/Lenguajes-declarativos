:- dynamic estado/1.
% estado(_{ jugador, conectado, misCartas:[], cartasMesa:[], bazaWinners:[],
%           pts:_{jugador1:0,jugador2:0}, mano, miTurno:false,
%           tipoTurno, opciones:[], eventos:[], terminada:false,
%           resultado }).
:- dynamic buffer_accion/1.
% buffer_accion(json_string)

inicializar :-
    retractall(estado(_)),
    retractall(buffer_accion(_)),
    assert(estado(_{ jugador:'', conectado:false, misCartas:[],
                     cartasMesa:[], bazaWinners:[],
                     pts:_{jugador1:0,jugador2:0}, mano:'',
                     miTurno:false, tipoTurno:'', opciones:[],
                     eventos:[], terminada:false, resultado:'' })).

conectar(Jugador) :-
    inicializar,
    retract(estado(E0)),
    E1 = E0.put(_{jugador:Jugador, conectado:true}),
    assert(estado(E1)),
    log_evento('Conectando...', conexion),
    format(string(JSON), '{"jugador":"~w"}', [Jugador]),
    assert(buffer_accion(JSON)).

procesar_mensaje_ws(MsgAtom) :-
    term_string(Term, MsgAtom),
    procesar_term(Term).

% cartas(Cartas) — convertir a strings para React
procesar_term(cartas(Cartas)) :-
    retract(estado(E)),
    maplist(term_string, Cartas, CartasStr),
    assert(estado(E.put(misCartas, CartasStr))),
    log_evento('Municion recibida', cartas).

% evento(MsgTerm) — delegar a handler
procesar_term(evento(Term)) :-
    manejar_evento(Term).

manejar_evento(inicio_partida) :-
    retract(estado(E)),
    assert(estado(E.put(_{cartasMesa:[], bazaWinners:[], miTurno:false,
                         terminada:false}))),
    log_evento('OPERACION INICIADA', titulo).

manejar_evento(partida_terminada(Ganador, Pts1, Pts2)) :-
    retract(estado(E)),
    format(string(Res), 'Victoria de ~w — ~w a ~w', [Ganador, Pts1, Pts2]),
    assert(estado(E.put(_{terminada:true, resultado:Res}))),
    log_evento(Res, titulo).

manejar_evento(estado_mano(Mano, P1, P2)) :-
    retract(estado(E)),
    assert(estado(E.put(_{pts:_{jugador1:P1, jugador2:P2}, mano:Mano}))),
    format(string(T), '~w - ~w | Mano: ~w', [P1, P2, Mano]),
    log_evento(T, puntaje).

manejar_evento(carta_jugada(Jugador, carta(N, P))) :-
    retract(estado(E)),
    format(string(CS), 'carta(~w,~w)', [N, P]),
    Mesa = E.cartasMesa,
    append(Mesa, [_{jugador:Jugador, carta:CS}], MesaN),
    % Si fui yo quien jugó, quitar la carta de mi mano
    (   Jugador == E.jugador
    ->  delete(E.misCartas, CS, CartasN),
        E2 = E.put(_{cartasMesa:MesaN, misCartas:CartasN})
    ;   E2 = E.put(cartasMesa, MesaN)
    ),
    assert(estado(E2)),
    format(string(T), '~w despliega ~w', [Jugador, CS]),
    log_evento(T, accion).

manejar_evento(ganador_baza(Ganador)) :-
    retract(estado(E)),
    Wins = E.bazaWinners,
    append(Wins, [Ganador], WinsN),
    assert(estado(E.put(bazaWinners, WinsN))),
    format(string(T), 'Baza para ~w', [Ganador]),
    log_evento(T, resultado).

manejar_evento(ganador_mano(Ganador, Ptos)) :-
    retract(estado(E)),
    assert(estado(E.put(_{cartasMesa:[], bazaWinners:[]}))),
    format(string(T), 'Mano: ~w — ~w pts', [Ganador, Ptos]),
    log_evento(T, resultado).

manejar_evento(estado_apuesta(EstadoApuesta)) :-
    format(string(T), 'Apuesta: ~w', [EstadoApuesta]),
    log_evento(T, info).

% Turnos — primero peek, solo retract después del cut
manejar_evento(Term) :-
    functor(Term, Tipo, 2),
    miembro(Tipo, [turno_carta, turno_apuesta, turno_retruco,
                   turno_vale4, responder_truco, responder_retruco,
                   responder_vale4]),
    arg(1, Term, Jugador),
    arg(2, Term, Opcs),
    estado(E),                % peek no destructivo
    Jugador == E.jugador,     % es mi turno?
    !,                        % sí → commit
    retract(estado(_)),       % ahora retiramos seguro
    assert(estado(E.put(_{miTurno:true, tipoTurno:Tipo, opciones:Opcs}))),
    log_evento(Term, turno).

% Turno sin opciones (ej: turno_vale4 a veces no tiene lista)
manejar_evento(Term) :-
    functor(Term, Tipo, 1),
    miembro(Tipo, [turno_carta, turno_apuesta, turno_retruco,
                   turno_vale4, responder_truco, responder_retruco,
                   responder_vale4]),
    arg(1, Term, Jugador),
    estado(E),
    Jugador == E.jugador,
    !,
    retract(estado(_)),
    assert(estado(E.put(_{miTurno:true, tipoTurno:Tipo, opciones:[]}))),
    log_evento(Term, turno).

% Turno del rival — no es mi turno, resetar tipoTurno y opciones
manejar_evento(Term) :-
    functor(Term, Tipo, _),
    miembro(Tipo, [turno_carta, turno_apuesta, turno_retruco,
                   turno_vale4, responder_truco, responder_retruco,
                   responder_vale4]),
    !,
    retract(estado(E)),
    assert(estado(E.put(_{miTurno:false, tipoTurno:'', opciones:[]}))),
    log_evento(Term, info).

% Cantos
manejar_evento(Term) :-
    functor(Term, Tipo, 1),
    miembro(Tipo, [canto_truco, canto_retruco, canto_vale4,
                   acepto_truco, no_quiero]),
    log_evento(Term, accion).

% Default
manejar_evento(Term) :-
    log_evento(Term, info).

miembro(X, [X|_]).
miembro(X, [_|T]) :- miembro(X, T).

encolar_accion(Valor) :-
    retractall(buffer_accion(_)),
    (   number(Valor)
    ->  format(string(JSON), '{"accion":~w}', [Valor])
    ;   format(string(JSON), '{"accion":"~w"}', [Valor])
    ),
    assert(buffer_accion(JSON)).

siguiente_envio(JSON) :-
    retract(buffer_accion(JSON)).

obtener_estado(E) :-
    estado(E).

log_evento(Term, Tipo) :-
    term_string(Term, Str),
    retract(estado(E)),
    Evs = E.eventos,
    append(Evs, [_{texto:Str, tipo:Tipo}], EvsN),
    assert(estado(E.put(eventos, EvsN))).
