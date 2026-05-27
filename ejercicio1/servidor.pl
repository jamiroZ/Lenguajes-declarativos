% WEBSOCKET SERVER

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/websocket)).
:- use_module(library(http/json)).

:- consult('truco.pl').

:- dynamic cliente/2.

% SERVER
server :-
    http_server(http_dispatch, [port(8080)]).


% HANDLER
:- http_handler(
    root(ws),
    http_upgrade_to_websocket(aceptar_ws, []),
    []
).

aceptar_ws(WebSocket) :-

    ws_receive(WebSocket, Mensaje, []),

    atom_json_dict(
        Mensaje.data,
        Dict,
        []
    ),

    Jugador = Dict.jugador,

    assertz(cliente(Jugador, WebSocket)),

    format('Conectado: ~w~n', [Jugador]),

    esperar_jugadores.

esperar_jugadores :-

    findall(J, cliente(J,_), Lista),

    length(Lista, 2),

    !,

    iniciar.

esperar_jugadores.

% IMPLEMENTACION PREDICADOS
pedir_accion(Jugador, Texto, Respuesta) :-

    enviar_mensaje(Jugador, Texto),

    cliente(Jugador, WS),

    ws_receive(WS, Mensaje, []),

    atom_json_dict(Mensaje.data, Dict, []),

    Valor = Dict.input,

    ( number(Valor) ->
        Respuesta = Valor
    ;
        atom_string(Respuesta, Valor)
    ).

mostrar_mensaje(Jugador, Texto) :-
    enviar_mensaje(Jugador, Texto).

mostrar_cartas_ws(Jugador, Cartas) :-

    term_string(Cartas, Texto),

    enviar_mensaje(
        Jugador,
        Texto
    ).

% ENVIAR
enviar_mensaje(Jugador, Texto) :-

    cliente(Jugador, WS),

    atom_json_dict(
        Atom,
        _{
            mensaje:Texto
        },
        []
    ),

    ws_send(
        WS,
        text(Atom)
    ).
carta_string(carta(N,P), Texto) :-format(string(Texto), '~w-~w', [N,P]).