:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/websocket)).
:- use_module(library(http/json)).
:- consult('truco.pl').

:- dynamic cliente/2.
:- dynamic cola_jugador/2.
:- dynamic partida_iniciada/0.

% ==========================================
% HANDLER
% ==========================================

:- http_handler(root(ws), websocket_handler, []).

server :-
    http_server(http_dispatch, [port(8080)]).

% ==========================================
% WEBSOCKET
% ==========================================

websocket_handler(Request) :-
    http_upgrade_to_websocket(
        aceptar_websocket,
        [],
        Request
    ).

aceptar_websocket(WS) :-

    ws_receive(WS, Mensaje, []),

    atom_json_dict(Mensaje.data, Dict, []),

    Jugador = Dict.jugador,

    message_queue_create(Cola),

    assertz(cliente(Jugador, WS)),
    assertz(cola_jugador(Jugador, Cola)),

    format("Jugador conectado: ~w~n", [Jugador]),

    thread_create(
        escuchar_jugador(Jugador, WS, Cola),
        _,
        []
    ),

    verificar_inicio,

    esperar.

% ==========================================
% MANTENER CONEXION VIVA
% ==========================================

esperar :-
    repeat,
    sleep(60),
    fail.

% ==========================================
% ESCUCHAR MENSAJES DEL CLIENTE
% ==========================================

escuchar_jugador(Jugador, WS, Cola) :-

    repeat,

    ws_receive(WS, Mensaje, []),

    (
        Mensaje.opcode == close
        ->
        format("Desconectado: ~w~n", [Jugador]),
        !

        ;

        atom_json_dict(Mensaje.data, Dict, []),

        (
            get_dict(accion, Dict, Accion)
            ->
            format("Accion de ~w: ~w~n", [Jugador, Accion]),

            thread_send_message(
                Cola,
                accion(Accion)
            )

            ;

            true
        ),

        fail
    ).

% ==========================================
% INICIAR PARTIDA
% ==========================================

verificar_inicio :-

    partida_iniciada,
    !.

verificar_inicio :-

    findall(J, cliente(J,_), Lista),

    length(Lista, Cant),

    Cant >= 2,

    assertz(partida_iniciada),

    writeln("INICIANDO PARTIDA"),

    thread_create(
        iniciar,
        _,
        []).

verificar_inicio.

% ==========================================
% MOTOR
% ==========================================

obtener_accion(Jugador, Accion) :-

    format("Esperando accion de ~w~n", [Jugador]),

    cola_jugador(Jugador, Cola),

    thread_get_message(
        Cola,
        accion(Valor)
    ),

    format("Recibido de ~w: ~w~n", [Jugador, Valor]),

    (
        number(Valor)
        ->
        Accion = Valor

        ;

        atom_string(Accion, Valor)
    ).

% ==========================================
% EVENTOS
% ==========================================

enviar_evento(todos, Evento) :-

    forall(
        cliente(_, WS),
        enviar_ws(WS, Evento)
    ).

enviar_evento(Jugador, Evento) :-

    cliente(Jugador, WS),

    enviar_ws(WS, Evento).

% ==========================================
% CARTAS
% ==========================================

enviar_cartas(Jugador, Cartas) :-

    cliente(Jugador, WS),

    term_string(Cartas, Texto),

    ws_send(
        WS,
        json(_{
            tipo: cartas,
            cartas: Texto
        })
    ).

% ==========================================
% ENVIO GENERICO
% ==========================================

enviar_ws(WS, Evento) :-

    term_string(Evento, Texto),

    ws_send(
        WS,
        json(_{
            tipo: evento,
            mensaje: Texto
        })
    ).