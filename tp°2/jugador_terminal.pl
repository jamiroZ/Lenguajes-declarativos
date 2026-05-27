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

    jugar_loop(WS).

% ==========================================

jugar_loop(WS) :-

    ws_receive(WS, Mensaje, []),

    (
        Mensaje.opcode == close
        ->
        writeln('Conexion cerrada')

        ;

        atom_json_dict(Mensaje.data, Dict, []),

        manejar(Dict, WS),

        jugar_loop(WS)
    ).

% ==========================================

manejar(Dict, WS) :-

    Tipo = Dict.tipo,

    (
        Tipo == cartas
        ->
        mostrar_cartas(Dict)

        ;

        Tipo == evento
        ->
        manejar_evento(Dict, WS)

        ;

        true
    ).

% ==========================================

mostrar_cartas(Dict) :-

    nl,
    writeln('===================='),
    writeln('TUS CARTAS'),
    writeln('===================='),

    writeln(Dict.cartas),
    nl.

% ==========================================

manejar_evento(Dict, WS) :-

    Evento = Dict.mensaje,

    nl,
    writeln('===================='),
    writeln('EVENTO'),
    writeln('===================='),

    writeln(Evento),

    (
        necesita_respuesta(Evento)
        ->
        responder(WS)

        ;

        true
    ).

% ==========================================

necesita_respuesta(Evento) :-
    sub_string(Evento, _, _, _, "turno_").

necesita_respuesta(Evento) :-
    sub_string(Evento, _, _, _, "responder_").

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