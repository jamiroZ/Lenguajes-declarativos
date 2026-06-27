:- module(main, [main/0]).

:- use_module(library(http/websocket)).
:- use_module(library(http/http_client)).
:- use_module(library(http/http_json)).
:- use_module(library(http/json)).

consulta_ia(Prompt, Respuesta) :-
    getenv('GROQ_API_KEY', ApiKey),
    atomic_list_concat(['Bearer ', ApiKey], Auth),

    Body = _{
        model: "llama-3.3-70b-versatile",
        messages: [
            _{
                role: "user",
                content: Prompt
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

main :-
    format("Conectando a ws://localhost:8080/ws~n", []),
    http_open_websocket("ws://localhost:8080/ws", WebSocket, []),
    Reply = _{
        data: _{
            nombre: groq
        }
    },
    ws_send(WebSocket, json(Reply)),
    escuchar_mensajes(WebSocket).


escuchar_mensajes(Stream) :-
    format("Esperando mensajes...~n", []),
    ws_receive(Stream, Message, []),
    procesar_mensaje(Stream, Message).

procesar_mensaje(Stream, Message) :-
    (   Message.opcode == close ->
        format("Conexión cerrada por el servidor~n", [])
    ;   atom_json_dict(Message.data, Dict, []),
        Accion = Dict.data.accion,
        Mensaje = Dict.data.mensaje,
        (   Accion == "stats" ->
            Puntajes = Dict.data.puntajes,
            format("Puntajes finales:~n", []),
            forall(
                member(P, Puntajes),
                format("~w: ~w~n", [P.nombre, P.puntos])
            ),
            format("Desconectando...~n", []),
            ws_close(Stream, 1000, "Cliente terminando")
        ;   Accion == "turno" ->
            manejar_turno(Stream)
        ;   Accion == "juego" ->
            Mano = Dict.data.mano,
            format("Mano: ~w~n", [Mano]),
            Pozo = Dict.data.pozo,
            format("Pozo: ~w~n", [Pozo]),
            format("Mensaje: ~w~n", [Mensaje]),
            escuchar_mensajes(Stream)
        ;   format("Mensaje: ~w~n", [Mensaje]),
            escuchar_mensajes(Stream)
        )
    ).

manejar_turno(Stream) :-
    format("¡Es tu turno!~n", []),

    format("¿Tomar del pozo o del mazo? (pozo/mazo)~n", []),

    PromptTomar = "Estás jugando Chinchón, debes elegir entre pozo o mazo. Responde únicamente con pozo o mazo. No agregues puntuación. No agregues mayúsculas. No expliques tu decisión.",
    consulta_ia(PromptTomar, OpcionTomarStr),
    format("IA responde: ~w~n", [OpcionTomarStr]),

    atom_string(OpcionTomar, OpcionTomarStr),

    ReplyTomar = _{
        data: _{
            desde: OpcionTomar
        }
    },
    ws_send(Stream, json(ReplyTomar)),

    ws_receive(Stream, RespTomar),
    atom_json_dict(RespTomar.data, DictTomar, []),

    Mano = DictTomar.data.mano,

    format("Nueva mano: ~w~n", [Mano]),

    format("¿Qué carta desea descartar?~n", []),

    format("Consultando IA...~n", []),
    format("Mano actual: ~w~n", [Mano]),

    format(string(PromptDejar),
        "Estás jugando Chinchón, tu mano es ~w. Elige exactamente una carta para descartar. Responde solamente con el formato palo-valor, por ejemplo oro-7. No agregues puntuación. No agregues mayúsculas. No expliques tu decisión.",
        [Mano]),

    consulta_ia(PromptDejar, CartaStr),
    format("IA responde: ~w~n", [CartaStr]),

    ReplyDejar = _{
        data: _{
            descarte: CartaStr
        }
    },
    ws_send(Stream, json(ReplyDejar)),

    ws_receive(Stream, RespDejar),
    atom_json_dict(RespDejar.data, DictDejar, []),

    format("Mano actual: ~w~n", [DictDejar.data.mano]),
    format("Pozo actual: ~w~n", [DictDejar.data.pozo]),

    format("¿Desea cerrar? (s/n)~n", []),

    format(string(PromptCerrar),
        "Estás jugando Chinchón, tu mano es ~w. Decide si cerrar, si no se cierra se continúa el juego. Responde únicamente con s o n. No agregues puntuación. No agregues mayúsculas. No expliques tu decisión.",
        [DictDejar.data.mano]),

    consulta_ia(PromptCerrar, OpcionCerrarStr),
    format("IA responde: ~w~n", [OpcionCerrarStr]),

    atom_string(OpcionCerrar, OpcionCerrarStr),

    ReplyCerrar = _{
        data: _{
            cerrar: OpcionCerrar
        }
    },
    ws_send(Stream, json(ReplyCerrar)),

    escuchar_mensajes(Stream).