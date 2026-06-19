:- use_module(library(http/websocket)).
:- use_module(library(http/http_open)).
:- use_module(library(http/json)).
:- use_module(library(readutil)).

conectar(Jugador) :-

    http_open_websocket(
        'ws://localhost:8080/ws',
        WS,
        []
    ),

    ws_send(
        WS,
        json(_{
            jugador: Jugador
        })
    ),

    format('Conectado como ~w~n', [Jugador]),
    jugar_loop(WS,Jugador).

% ==========================================

jugar_loop(WS, Jugador) :-
    ws_receive(WS, Mensaje, []),
    (
        Mensaje.opcode == close
        ->
        writeln('Conexion cerrada')
        ;
        atom_json_dict(Mensaje.data, Dict, []),
        manejar(Dict, WS, Jugador),
        jugar_loop(WS, Jugador)
).

% ==========================================

manejar(Dict, WS, Jugador) :-

    atom_string(TipoAtom, Dict.tipo),

    (
        TipoAtom == cartas
        ->
        mostrar_cartas(Dict)

        ;

        TipoAtom == evento
        ->
        manejar_evento(Dict, WS, Jugador)

        ;

        writeln('TIPO DESCONOCIDO')
    ).

% ==========================================

mostrar_cartas(Dict) :-

    atom_string(AtomCartas, Dict.cartas),
    term_string(ListaCartas, AtomCartas),
    nl,
    writeln('================================='),
    writeln('TUS CARTAS'),
    writeln('================================='),
    mostrar_cartas_num(ListaCartas,1),
    nl.

mostrar_cartas_num([], _).

mostrar_cartas_num([C|R], N) :-
    format('~w -> ~w~n',[N,C]),
    N2 is N + 1,
    mostrar_cartas_num(R,N2).
% ==========================================

manejar_evento(Dict, WS, Jugador) :-

    Evento = Dict.mensaje,
    catch(
       
        term_string(Termino, Evento),
        E,
        (
            writeln('ERROR EN term_string'),
            writeln(E),
            fail
        )
    ),

    mostrar_evento(Termino),

    (
        es_mi_turno(Evento, Jugador)
        -> 
        responder(WS)
        ;
        true
    ).

% ==========================================

responder(WS) :-

    nl,
    write('Ingresar accion: '),

    read_line_to_string(user_input, Texto),

    convertir(Texto, Valor),

    ws_send(
        WS,
        json(_{
            accion: Valor
        })
    ).

% ==========================================

convertir(Texto, Numero) :-
    number_string(Numero, Texto),
    !.

convertir(Texto, Atom) :-
    atom_string(Atom, Texto).

es_mi_turno(Evento, Jugador) :-
    
    atom_string(AtomEvento, Evento),
    catch(
        term_string(Termino, AtomEvento),
        _,
        fail
    ),
    (
        Termino = turno_apuesta(Jugador,_)
        ;
        Termino = turno_carta(Jugador)
        ;
        Termino = turno_retruco(Jugador,_)
        ;
        Termino = turno_vale4(Jugador)
        ;
        Termino = responder_truco(Jugador,_)
        ;
        Termino = responder_retruco(Jugador,_)
        ;
        Termino = responder_vale4(Jugador,_)
    ).


mostrar_evento(estado_apuesta(Estado)) :-

    nl,
    writeln('===================='),
    writeln('APUESTA ACTUAL'),
    writeln('===================='),

    format('~w~n',[Estado]).

mostrar_evento(inicio_partida) :-
    nl,
    writeln('===================='),
    writeln('INICIO DE PARTIDA'),
    writeln('====================').

mostrar_evento(carta_jugada(J,C)) :-
    format("~n~w jugó ~w~n",[J,C]).

mostrar_evento(canto_truco(J)) :-
    format("~n~w cantó TRUCO~n",[J]).

mostrar_evento(canto_retruco(J)) :-
    format("~n~w cantó RETRUCO~n",[J]).

mostrar_evento(canto_vale4(J)) :-
    format("~n~w cantó VALE 4~n",[J]).

mostrar_evento(acepto_truco(J)) :-
    format("~n~w aceptó el truco~n",[J]).

mostrar_evento(no_quiero(J)) :-
    format("~n~w no quiso~n",[J]).

mostrar_evento(ganador_baza(J)) :-

    nl,
    writeln('===================='),
    writeln('RESULTADO DE LA BAZA'),
    writeln('===================='),

    format('Ganó: ~w~n',[J]).

mostrar_evento(ganador_mano(J,Puntos)) :-

    nl,
    writeln('===================='),
    writeln('FIN DE LA MANO'),
    writeln('===================='),

    format('Ganador: ~w~n',[J]),
    format('Puntos obtenidos: ~w~n',[Puntos]).

mostrar_evento(estado_mano(_,P1,P2)) :-
    format(
        "~n====================~nPUNTAJE~n====================~nJugador1: ~w~nJugador2: ~w~n",
        [P1,P2]
    ).
mostrar_evento(turno_apuesta(Jugador, Opciones)) :-

    nl,
    writeln('===================='),
    writeln('TURNO DE APUESTA'),
    writeln('===================='),

    format('Jugador: ~w~n',[Jugador]),
    format('Opciones: ~w~n',[Opciones]).

mostrar_evento(turno_carta(Jugador)) :-

    nl,
    writeln('===================='),
    writeln('TURNO DE CARTA'),
    writeln('===================='),

    format('Jugador: ~w~n',[Jugador]).

% IMPORTANTE: SIEMPRE AL FINAL
mostrar_evento(Evento) :-
    format("~n[EVENTO] ~w~n",[Evento]).