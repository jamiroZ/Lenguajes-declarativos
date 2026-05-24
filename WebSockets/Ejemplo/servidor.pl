:- use_module(library(http/http_files)).
:- use_module(library(http/html_write)).
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/websocket)).
:- use_module(library(http/json)).

:- dynamic esperando/3.

% esperando(Nombre, Jugada, WS)

:- http_handler(root(ws), websocket_handler, []).
:- http_handler(root(''), inicio, []).

iniciar :-
    http_server(http_dispatch, [port(8080)]),
    writeln('Servidor iniciado en puerto 8080').
inicio(Request) :-
    http_reply_file(
        'index.html',
        [],
        Request
    ).

websocket_handler(Request) :-
    http_upgrade_to_websocket(
        atender_cliente,
        [],
        Request).

atender_cliente(WS) :-

    ws_receive(WS, Mensaje),

    Mensaje.opcode == text,

    split_string(
        Mensaje.data,
        ",",
        "",
        [NombreStr, JugadaStr]
    ),

    atom_string(Nombre, NombreStr),
    atom_string(Jugada, JugadaStr),

    format('~w jugó ~w~n', [Nombre, Jugada]),

    manejar_jugador(Nombre, Jugada, WS).

% primer jugador espera

manejar_jugador(Nombre, Jugada, WS) :-

    \+ esperando(_,_,_),

    assertz(esperando(Nombre, Jugada, WS)),

    writeln('Esperando otro jugador...'),

    repeat,

    sleep(1),

    \+ esperando(Nombre, Jugada, WS),

    !.

% segundo jugador
manejar_jugador(Nombre2, Jugada2, WS2) :-

    retract(esperando(Nombre1, Jugada1, WS1)),

    ganador(Jugada1, Jugada2, Resultado),

    format(
        'Partida: ~w vs ~w -> ~w~n',
        [Nombre1, Nombre2, Resultado]
    ),

    atomic_list_concat(
        ['Tu jugada: ', Jugada1,
         ' | Rival: ', Nombre2,
         ' | Resultado: ', Resultado],
        Msg1
    ),

    atomic_list_concat(
        ['Tu jugada: ', Jugada2,
         ' | Rival: ', Nombre1,
         ' | Resultado: ', Resultado],
        Msg2
    ),

    catch(
        ws_send(WS1, text(Msg1)),
        _,
        writeln('Jugador 1 desconectado')
    ),

    catch(
        ws_send(WS2, text(Msg2)),
        _,
        writeln('Jugador 2 desconectado')
    ).

% lógica del juego

ganador(X, X, empate).

ganador(piedra, tijera, jugador1).
ganador(tijera, papel, jugador1).
ganador(papel, piedra, jugador1).

ganador(tijera, piedra, jugador2).
ganador(papel, tijera, jugador2).
ganador(piedra, papel, jugador2).