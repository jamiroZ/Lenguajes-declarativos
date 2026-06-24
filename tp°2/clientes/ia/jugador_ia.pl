:- use_module(library(http/websocket)).
:- use_module(library(lists)).

% Estado dinámico local para almacenar la información de la partida
:- dynamic mis_cartas/1.
:- dynamic ultimo_evento/1.
:- dynamic rondas_ganadas/1.
:- dynamic rondas_perdidas/1.

%  iniciar_ia(+Nombre)
%  Se conecta al servidor central de WebSockets e inicia el bucle de escucha.
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

%  bucle_ia(+WS, +Nombre)
%  Recibe los datos del WebSocket, extrae de forma segura el texto y procesa el evento.
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

% =========================================================================
% PROCESAMIENTO DE EVENTOS
% =========================================================================

% Caso 1: El servidor manda las cartas asignadas
procesar_evento(Dict, _WS, _Nombre) :-
    get_dict(tipo, Dict, "cartas"), !,
    get_dict(cartas, Dict, CartasTexto),
    format("[MEMORIA IA] Mis cartas asignadas: ~w~n", [CartasTexto]),
    retractall(mis_cartas(_)),
    assertz(mis_cartas(CartasTexto)),
    retractall(rondas_ganadas(_)),
    retractall(rondas_perdidas(_)),
    assertz(rondas_ganadas(0)),
    assertz(rondas_perdidas(0)).

% Caso 1b: carta_jugada nuestro - actualizar mis cartas
procesar_evento(Dict, WS, Nombre) :-
    ( get_dict(tipo, Dict, "evento") ; get_dict(tipo, Dict, evento) ), !,
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

procesar_evento(_, _, _).

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

%  es_mi_turno(+Evento, +Jugador)
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

% =========================================================================
% IA LOCAL - ESTRATEGIA DE TRUCO
% =========================================================================

% Valores de las cartas (mismos que el motor)
valor_carta(carta(1, espada), 14).
valor_carta(carta(1, basto), 13).
valor_carta(carta(7, espada), 12).
valor_carta(carta(7, oro), 11).
valor_carta(carta(3, _), 10).
valor_carta(carta(2, _), 9).
valor_carta(carta(1, _), 8) :- !.
valor_carta(carta(12, _), 7).
valor_carta(carta(11, _), 6).
valor_carta(carta(10, _), 5).
valor_carta(carta(7, _), 4) :- !.
valor_carta(carta(6, _), 3).
valor_carta(carta(5, _), 2).
valor_carta(carta(4, _), 1).

%  ejecutar_turno_ia(+WS)
%  Decide y envía la mejor acción según el estado actual.
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

% =========================================================================
% DECISIONES DE APUESTAS
% =========================================================================

% Poder medio de la mano
poder_medio(Cartas, Avg) :-
    maplist(valor_carta, Cartas, Valores),
    sum_list(Valores, Sum),
    length(Cartas, N),
    Avg is Sum / N.

poder_maximo(Cartas, Max) :-
    maplist(valor_carta, Cartas, Valores),
    max_list(Valores, Max).

poder_minimo(Cartas, Min) :-
    maplist(valor_carta, Cartas, Valores),
    min_list(Valores, Min).

% Responder al Truco
decidir_accion(Cartas, responder_truco(_, Opciones), Accion) :-
    poder_medio(Cartas, Avg),
    poder_maximo(Cartas, Max),
    (   Max >= 12, Avg >= 9, member(retruco, Opciones)
    ->  Accion = 'retruco'
    ;   Avg >= 7
    ->  Accion = 'quiero'
    ;   Accion = 'no'
    ).

% Responder al Retruco
decidir_accion(Cartas, responder_retruco(_, Opciones), Accion) :-
    poder_medio(Cartas, Avg),
    poder_maximo(Cartas, Max),
    (   Max >= 12, Avg >= 10, member(vale4, Opciones)
    ->  Accion = 'vale4'
    ;   Avg >= 8
    ->  Accion = 'quiero'
    ;   Accion = 'no'
    ).

% Responder al Vale 4
decidir_accion(Cartas, responder_vale4(_, Opciones), Accion) :-
    poder_medio(Cartas, Avg),
    (   Avg >= 10, member(quiero, Opciones)
    ->  Accion = 'quiero'
    ;   Accion = 'no'
    ).

% Turno de apuesta (cantar truco o pasar)
decidir_accion(Cartas, turno_apuesta(_, Opciones), Accion) :-
    poder_medio(Cartas, Avg),
    (   Avg >= 9, member(truco, Opciones)
    ->  Accion = 'truco'
    ;   Accion = 'nada'
    ).

% Turno de retruco
decidir_accion(Cartas, turno_retruco(_, Opciones), Accion) :-
    poder_medio(Cartas, Avg),
    (   Avg >= 10, member(retruco, Opciones)
    ->  Accion = 'retruco'
    ;   Accion = 'nada'
    ).

% Turno de vale4
decidir_accion(_Cartas, turno_vale4(_), Accion) :-
    Accion = 'nada'.

% =========================================================================
% DECISIONES DE CARTAS A JUGAR
% =========================================================================

decidir_accion(Cartas, turno_carta(_), Accion) :-
    rondas_ganadas(RG),
    rondas_perdidas(RP),
    
    % Estrategia: ordenar por poder ascendente
    sort_cartas_by_power(Cartas, Sorted),
    
    % Decidir qué carta jugar según el contexto
    (   RP >= 2
    ->  % Perdimos 2 rondas, jugar la mejor
        reverse(Sorted, [Mejor|_]),
        nth1(Pos, Cartas, Mejor),
        Accion = Pos
    ;   RP = 1, RG = 0
    ->  % Vamos perdiendo, jugar la mejor
        reverse(Sorted, [Mejor|_]),
        nth1(Pos, Cartas, Mejor),
        Accion = Pos
    ;   % Situación normal, jugar la peor (sacrificio)
        Sorted = [Peor|_],
        nth1(Pos, Cartas, Peor),
        Accion = Pos
    ).

% Ordenar cartas por poder ascendente
sort_cartas_by_power(Cartas, Sorted) :-
    maplist(valor_carta, Cartas, Valores),
    pairs_keys_values(Pairs, Valores, Cartas),
    sort(Pairs, SortedPairs),
    pairs_values(SortedPairs, Sorted).