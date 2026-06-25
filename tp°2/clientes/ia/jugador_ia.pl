:- use_module(library(http/websocket)).
:- use_module(library(http/http_client)).
:- use_module(library(http/http_json)).
:- use_module(library(lists)).

:- dynamic mis_cartas/1.
:- dynamic ultimo_evento/1.
:- dynamic rondas_ganadas/1.
:- dynamic rondas_perdidas/1.

iniciar_ia(Nombre) :-
    iniciar_ia(Nombre, localhost).

iniciar_ia(Nombre, Host) :-
    format(string(URL), 'ws://~w:8080/ws', [Host]),
    format("Intentando conectar a ~w...~n", [URL]),
    http_open_websocket(URL, WS, []),
    format("Conectado al servidor de Truco como ~w~n", [Nombre]),
    
    DictRegistro = _{jugador: Nombre},
    atom_json_dict(MensajeRegistro, DictRegistro, []),
    ws_send(WS, text(MensajeRegistro)),
    
    assertz(ultimo_evento("Inicio de partida")),
    assertz(rondas_ganadas(0)),
    assertz(rondas_perdidas(0)),
    bucle_ia(WS, Nombre).

bucle_ia(WS, Nombre) :-
    repeat,
    ws_receive(WS, Mensaje, []),
    (   Mensaje.opcode == close
    ->  writeln("El servidor cerró la conexión."), !
    ;   ( Mensaje.data = Data -> true ; Mensaje = text(Data) ),
        atom_json_dict(Data, Dict, []),
        catch(procesar_evento(Dict, WS, Nombre), Error, format("Error procesando evento: ~w~n", [Error])),
        fail
    ).

procesar_evento(Dict, _WS, _Nombre) :-
    get_dict(tipo, Dict, TipoCartas),
    (TipoCartas == cartas ; TipoCartas == "cartas"), !,
    get_dict(cartas, Dict, CartasTexto),
    format("[MEMORIA IA] Mis cartas asignadas: ~w~n", [CartasTexto]),
    retractall(mis_cartas(_)),
    assertz(mis_cartas(CartasTexto)),
    retractall(rondas_ganadas(_)),
    retractall(rondas_perdidas(_)),
    assertz(rondas_ganadas(0)),
    assertz(rondas_perdidas(0)).

procesar_evento(Dict, WS, Nombre) :-
    get_dict(tipo, Dict, TipoEvento),
    (TipoEvento == evento ; TipoEvento == "evento"), !,
    get_dict(mensaje, Dict, TextoEvento),
    format("[RED] Evento de mesa: ~w~n", [TextoEvento]),
    
    retractall(ultimo_evento(_)),
    assertz(ultimo_evento(TextoEvento)),
    
    (   es_carta_jugada_mia(TextoEvento, Nombre)
    ->  actualizar_cartas(TextoEvento)
    ;   true
    ),
    
    (   es_baza_ganada_mia(TextoEvento, Nombre)
    ->  retract(rondas_ganadas(N)), N2 is N + 1, assertz(rondas_ganadas(N2))
    ;   true
    ),
    (   es_baza_perdida_mia(TextoEvento, Nombre)
    ->  retract(rondas_perdidas(N)), N2 is N + 1, assertz(rondas_perdidas(N2))
    ;   true
    ),
    
    (   es_mi_turno(TextoEvento, Nombre)
    ->  writeln("[IA] Detecte mi turno! Analizando jugada..."),
        ejecutar_turno_ia(WS)
    ;   true
    ).

procesar_evento(Dict, _, _) :-
    format("[IA DEBUG] Evento desconocido: ~w~n", [Dict]).

es_carta_jugada_mia(TextoEvento, Nombre) :-
    atom_string(AtomEvento, TextoEvento),
    catch(term_string(Termino, AtomEvento), _, fail),
    Termino = carta_jugada(Nombre, _).

es_baza_ganada_mia(TextoEvento, Nombre) :-
    atom_string(AtomEvento, TextoEvento),
    catch(term_string(Termino, AtomEvento), _, fail),
    Termino = ganador_baza(Ganador),
    Ganador == Nombre.

es_baza_perdida_mia(TextoEvento, Nombre) :-
    atom_string(AtomEvento, TextoEvento),
    catch(term_string(Termino, AtomEvento), _, fail),
    Termino = ganador_baza(Ganador),
    Ganador \== Nombre.

actualizar_cartas(TextoEvento) :-
    mis_cartas(CartasTexto),
    atom_string(AtomEvento, TextoEvento),
    term_string(Termino, AtomEvento),
    Termino = carta_jugada(_, CartaJugada),
    term_string(Cartas, CartasTexto),
    select(CartaJugada, Cartas, Restantes),
    term_string(Restantes, NuevoTexto),
    retractall(mis_cartas(_)),
    assertz(mis_cartas(NuevoTexto)),
    format("[MEMORIA IA] Carta jugada: ~w, restantes: ~w~n", [CartaJugada, Restantes]).

es_mi_turno(Evento, Jugador) :-
    atom_string(AtomJugador, Jugador),
    atom_string(AtomEvento, Evento),
    catch(term_string(Termino, AtomEvento), _, fail),
    (   Termino = turno_apuesta(Target, _)
    ;   Termino = turno_carta(Target)
    ;   Termino = turno_retruco(Target, _)
    ;   Termino = turno_vale4(Target)
    ;   Termino = responder_truco(Target, _)
    ;   Termino = responder_retruco(Target, _)
    ;   Termino = responder_vale4(Target, _)
    ),
    atom_string(AtomTarget, Target),
    AtomTarget == AtomJugador.

consulta_ia(Prompt, Respuesta) :-
    getenv('GROQ_API_KEY', ApiKey),
    atomic_list_concat(['Bearer ', ApiKey], Auth),
    Body = _{
        model: "llama-3.3-70b-versatile",
        messages: [
            _{ role: "user", content: Prompt }
        ]
    },
    catch(
        http_post(
            'https://api.groq.com/openai/v1/chat/completions',
            json(Body),
            Dict,
            [
                request_header('Authorization'=Auth),
                json_object(dict),
                timeout(30)
            ]
        ),
        Error,
        (format("[IA] Error HTTP a Groq: ~w~n", [Error]), fail)
    ),
    [Choice|_] = Dict.choices,
    Respuesta = Choice.message.content.

normalizar_respuesta(Str, Resultado) :-
    string_codes(Str, Codes),
    filtrar_codigos(Codes, Limpios),
    string_codes(Limpio, Limpios),
    atom_string(Atom, Limpio),
    downcase_atom(Atom, Down),
    (   catch(number_string(Num, Down), _, fail)
    ->  Resultado = Num
    ;   Resultado = Down
    ).

filtrar_codigos([], []).
filtrar_codigos([C|R], Limpios) :-
    ( C < 32 ; C =:= 0x22 ; C =:= 0x27 ; C =:= 0x2E ; C =:= 0x60 ),
    !, filtrar_codigos(R, Limpios).
filtrar_codigos([C|R], [C|Limpios]) :-
    filtrar_codigos(R, Limpios).

ejecutar_turno_ia(WS) :-
    (mis_cartas(CartasTexto) -> true ; CartasTexto = "[]"),
    ultimo_evento(Contexto),
    
    format("[IA] Cartas: ~w~n", [CartasTexto]),
    format("[IA] Contexto: ~w~n", [Contexto]),
    
    term_string(Cartas, CartasTexto),
    atom_string(AtomContexto, Contexto),
    catch(term_string(TerminoContexto, AtomContexto), _, fail),
    
    decidir_accion(Cartas, TerminoContexto, Accion),
    
    format("[IA] Decisión: ~w~n", [Accion]),
    DictEnviar = _{accion: Accion},
    atom_json_dict(MensajeEnviar, DictEnviar, []),
    ws_send(WS, text(MensajeEnviar)),
    writeln("[IA] Acción enviada correctamente.").

decidir_accion(Cartas, Contexto, Accion) :-
    prompt_para_contexto(Contexto, Cartas, Prompt),
    format("[IA] Consultando LLM...~n", []),
    (   catch(consulta_ia(Prompt, RespuestaCruda), _, fail)
    ->  format("[IA] LLM responde: ~w~n", [RespuestaCruda]),
        normalizar_respuesta(RespuestaCruda, Accion)
    ;   format("[IA] LLM fallo, usando accion por defecto~n", []),
        accion_por_defecto(Contexto, Accion)
    ).

accion_por_defecto(responder_truco(_, Opciones), Accion) :-
    Opciones = [Accion|_].
accion_por_defecto(responder_retruco(_, Opciones), Accion) :-
    Opciones = [Accion|_].
accion_por_defecto(responder_vale4(_, Opciones), Accion) :-
    Opciones = [Accion|_].
accion_por_defecto(turno_apuesta(_, Opciones), Accion) :-
    Opciones = [Accion|_].
accion_por_defecto(turno_retruco(_, Opciones), Accion) :-
    Opciones = [Accion|_].
accion_por_defecto(turno_vale4(_), Accion) :-
    Accion = nada.
accion_por_defecto(turno_carta(_), Accion) :-
    Accion = 1.

prompt_para_contexto(responder_truco(_, Opciones), Cartas, Prompt) :-
    format(string(Prompt),
        "Estas jugando al Truco argentino. Tu mano es: ~w. El rival canto truco. Opciones: ~w. Responde unicamente con una de las opciones, sin explicacion, sin mayusculas, sin puntuacion.",
        [Cartas, Opciones]).

prompt_para_contexto(responder_retruco(_, Opciones), Cartas, Prompt) :-
    format(string(Prompt),
        "Estas jugando al Truco argentino. Tu mano es: ~w. El rival canto retruco. Opciones: ~w. Responde unicamente con una de las opciones, sin explicacion, sin mayusculas, sin puntuacion.",
        [Cartas, Opciones]).

prompt_para_contexto(responder_vale4(_, Opciones), Cartas, Prompt) :-
    format(string(Prompt),
        "Estas jugando al Truco argentino. Tu mano es: ~w. El rival canto vale cuatro. Opciones: ~w. Responde unicamente con una de las opciones, sin explicacion, sin mayusculas, sin puntuacion.",
        [Cartas, Opciones]).

prompt_para_contexto(turno_apuesta(_, Opciones), Cartas, Prompt) :-
    format(string(Prompt),
        "Estas jugando al Truco argentino. Tu mano es: ~w. Es tu turno de apuesta. Opciones: ~w. Responde unicamente con una de las opciones, sin explicacion, sin mayusculas, sin puntuacion.",
        [Cartas, Opciones]).

prompt_para_contexto(turno_retruco(_, Opciones), Cartas, Prompt) :-
    format(string(Prompt),
        "Estas jugando al Truco argentino. Tu mano es: ~w. Es tu turno. Opciones: ~w. Responde unicamente con una de las opciones, sin explicacion, sin mayusculas, sin puntuacion.",
        [Cartas, Opciones]).

prompt_para_contexto(turno_vale4(_), Cartas, Prompt) :-
    format(string(Prompt),
        "Estas jugando al Truco argentino. Tu mano es: ~w. Puedes cantar vale4 o pasar. Responde unicamente con vale4 o nada, sin explicacion, sin mayusculas, sin puntuacion.",
        [Cartas]).

prompt_para_contexto(turno_carta(_), Cartas, Prompt) :-
    format(string(Prompt),
        "Estas jugando al Truco argentino. Tu mano es: ~w. Es tu turno de jugar una carta. Elige la posicion numerica (1, 2 o 3) de la carta que quieres jugar. Responde unicamente con el numero.",
        [Cartas]).
