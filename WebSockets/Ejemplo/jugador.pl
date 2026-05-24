:- use_module(library(http/websocket)).
:- use_module(library(http/http_open)).
:- use_module(library(http/json)).

jugar(Nombre, Jugada) :-

    http_open_websocket(
        'ws://localhost:8080/ws',
        WS,
        []
    ),

    atomic_list_concat(
        [Nombre, ',', Jugada],
        Mensaje
    ),

    ws_send(WS, text(Mensaje)),

    writeln('Esperando resultado...'),

    ws_receive(WS, Respuesta),

    writeln('Resultado recibido:'),

    writeln(Respuesta.data),

    ws_close(WS, 1000, "fin").