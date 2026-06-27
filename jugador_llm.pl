:- module(main, [main/0]).

:- use_module(library(http/websocket)).
:- use_module(library(http/http_client)).
:- use_module(library(http/http_json)).
:- use_module(library(http/json)).

:- dynamic mano_actual/1.
:- dynamic estado_apuesta/1.
:- dynamic cartas_jugadas/1.

mano_actual("[]").
estado_apuesta(nada).
cartas_jugadas([]).

%% CONSULTA A GROQ
consulta_ia(Prompt, Respuesta) :-

    format("LLAMANDO IA~n", []),

    getenv('GROQ_API_KEY', ApiKey),

    format("IA LLAMADA CON APIKEY~n", []),

    atomic_list_concat(
        ['Bearer ', ApiKey],
        Auth
    ),

    Body = _{
        model:"llama-3.3-70b-versatile",
        temperature:0.2,
        messages:[
            _{
                role:"system",
                content:"Eres un jugador experto de Truco Argentino. Responde únicamente con una acción válida. Nunca expliques tu respuesta."
            },
            _{
                role:"user",
                content:Prompt
            }
        ]
    },

    http_post(
        'https://api.groq.com/openai/v1/chat/completions',
        json(Body),
        Dict,
        [
            request_header('Authorization'=Auth),
            json_object(dict)
        ]
    ),

    [Choice|_] = Dict.choices,
    Respuesta = Choice.message.content.

%% MAIN
main :-
    writeln('Conectando...'),
    http_open_websocket(
        'ws://localhost:8080/ws',
        WS,
        []
    ),
    ws_send(
        WS,
        json(_{
            jugador:"groq"
        })
    ),

    escuchar(WS).

%% LOOP
escuchar(WS) :-
    ws_receive(
        WS,
        Msg,
        []
    ),

    procesar(WS, Msg),
    (
        Msg.opcode == close
        ->
        true
        ;
        escuchar(WS)
    ).

%% MENSAJES
procesar(_, Msg) :-
    Msg.opcode == close,
    !,

    writeln("Conexion cerrada.").

procesar(WS, Msg) :-

    atom_json_dict(
        Msg.data,
        Dict,
        []
    ),

    Tipo = Dict.tipo,

    (
        Tipo == "cartas"
        ->
        retractall(mano_actual(_)),
        assertz(mano_actual(Dict.cartas)),

        format(
            "Cartas: ~w~n",
            [Dict.cartas]
        )
        ;
        Tipo == "evento"
        ->
        procesar_evento(
            WS,
            Dict.mensaje
        )
        ;
        true
    ).

%% EVENTOS
procesar_evento(WS, Texto) :-
    atom_to_term(
        Texto,
        Evento,
        _
    ),
    format(
        "Evento: ~w~n",
        [Evento]
    ),
    (
        Evento = inicio_partida
        ->
        writeln("Inicio de partida")
    ;
        Evento = estado_mano(Mano,P1,P2)
        ->
        format(
            "Mano: ~w  Puntaje: ~w - ~w~n",
            [Mano,P1,P2]
        )
    ;
        Evento = estado_apuesta(Estado)
        ->
        retractall(estado_apuesta(_)),
        assertz(
            estado_apuesta(Estado)
        )
    ;
        Evento = carta_jugada(Jugador,Carta)
        ->
        cartas_jugadas(L),

        retractall(cartas_jugadas(_)),
        assertz(
            cartas_jugadas(
                [jugada(Jugador,Carta)|L]
            )
        )
    ;
        Evento = ganador_baza(G)
        ->
        format(
            "Ganador baza: ~w~n",
            [G]
        )

    ;
        Evento = ganador_mano(G,P)
        ->
        format(
            "Ganador mano: ~w (+~w)~n",
            [G,P]
        ),

        retractall(cartas_jugadas(_)),
        assertz(cartas_jugadas([])),

        retractall(estado_apuesta(_)),
        assertz(estado_apuesta(nada))
    ;
        Evento = partida_terminada(G,P1,P2)
        ->
        format(
            "Partida terminada.~nGanador: ~w~nResultado: ~w - ~w~n",
            [G,P1,P2]
        ),

        ws_close(
            WS,
            1000,
            "fin"
        )
    ;
        Evento = canto_truco(J)
        ->
        format("~w canto truco~n",[J])
    ;
        Evento = canto_retruco(J)
        ->
        format("~w canto retruco~n",[J])
    ;
        Evento = canto_vale4(J)
        ->
        format("~w canto vale4~n",[J])
    ;
        Evento = acepto_truco(J)
        ->
        format("~w acepto truco~n",[J])
    ;
        Evento = no_quiero(J)
        ->
        format("~w no quiso~n",[J])
    ;
        Evento = turno_apuesta(groq,Opciones)
        ->
        decidir_apuesta(
            WS,
            Opciones
        )
    ;
        Evento = turno_retruco(groq,Opciones)
        ->
        decidir_apuesta(
            WS,
            Opciones
        )
    ;
        Evento = responder_truco(groq,Opciones)
        ->
        decidir_apuesta(
            WS,
            Opciones
        )
    ;
        Evento = responder_retruco(groq,Opciones)
        ->
        decidir_apuesta(
            WS,
            Opciones
        )
    ;
        Evento = responder_vale4(groq,Opciones)
        ->
        decidir_apuesta(
            WS,
            Opciones
        )
    ;
        Evento = turno_vale4(groq)
        ->
        decidir_apuesta(
            WS,
            [vale4,nada]
        )
    ;
        Evento = turno_carta(groq)
        ->
        decidir_carta(
            WS
        )
    ;
        true
    ).
    
%% DECISION DE APUESTA
decidir_apuesta(WS, Opciones) :-

    mano_actual(Mano),
    estado_apuesta(Estado),
    cartas_jugadas(Jugadas),

    format(
        string(Prompt),
        "Estás jugando Truco Argentino.\c
        Tus cartas son:\c~w\c
        Estado actual de la apuesta:\c~w\c
        Cartas jugadas hasta el momento:\c~w\c
        Las únicas respuestas válidas son:\c~w\c
        Elegí la mejor acción para maximizar la probabilidad de ganar la partida.\c
        Respondé únicamente con una de las opciones exactamente igual, sin explicación.",
        [Mano, Estado, Jugadas, Opciones]
    ),

    format("Consultando IA...~n", []),

    consulta_ia(Prompt, Respuesta),

    normalize_space(string(RespuestaLimpia), Respuesta),

    format("IA respondió: ~w~n", [RespuestaLimpia]),

    enviar_accion(
        WS,
        RespuestaLimpia
    ).

%% DECISION DE CARTA
decidir_carta(WS) :-

    mano_actual(Mano),
    estado_apuesta(Estado),
    cartas_jugadas(Jugadas),

    format(
        string(Prompt),
        "Estás jugando Truco Argentino.\c
        Tus cartas son:\c~w\c
        Estado actual de la apuesta:\c~w\c
        Cartas jugadas hasta el momento:\c~w\c
        Elegí la mejor carta para jugar.\c            
        Respondé SOLO con un número: 1, 2 o 3.
        Nada más.
        Sin agregar texto.",
        [Mano, Estado, Jugadas]
    ),

    format("Consultando IA...~n", []),

    consulta_ia(Prompt, Respuesta),

    normalize_space(string(RespuestaLimpia), Respuesta),

    format("IA respondió: ~w~n", [RespuestaLimpia]),

    enviar_accion(
        WS,
        RespuestaLimpia
    ).

%% ENVIO
enviar_accion(WS, Accion) :-
    ws_send(
        WS,
        json(_{
            accion: Accion
        })
    ),

    format("Enviado: ~w~n", [Accion]).
