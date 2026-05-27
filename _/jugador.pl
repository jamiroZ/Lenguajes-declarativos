% ==========================================
% JUGADOR.PL — CLIENTE WEBSOCKET PARA TRUCO
% SWI-Prolog
%
% Cada instancia de este archivo ES un jugador en red.
% Se conecta al servidor truco_server.pl por WebSocket
% y permite jugar desde la terminal de Prolog.
%
% USO:
%   Terminal 1 (servidor):
%     $ swipl truco_server.pl
%     ?- iniciar_servidor(8080).
%
%   Terminal 2 (jugador 1):
%     $ swipl jugador.pl
%     ?- conectar('localhost', 8080).
%
%   Terminal 3 (jugador 2):
%     $ swipl jugador.pl
%     ?- conectar('localhost', 8080).
% ==========================================

:- use_module(library(http/websocket)).
:- use_module(library(http/http_open)).
:- use_module(library(http/json)).
:- use_module(library(lists)).

% ==========================================
% ESTADO LOCAL DEL JUGADOR
% ==========================================

% mi_jugador(?Rol)          -- jugador1 | jugador2
% mis_cartas(?ListaCartas)  -- [{numero:N, palo:P}, ...]
% turno_actual(?Jugador)
% estado_apuesta(?Estado)
% puntaje(?J1, ?J2)
% mi_ws(?WebSocket)

:- dynamic mi_jugador/1.
:- dynamic mis_cartas/1.
:- dynamic turno_actual/1.
:- dynamic estado_apuesta/1.
:- dynamic puntaje/2.
:- dynamic mi_ws/1.
:- dynamic ronda_actual/1.
:- dynamic partida_activa/0.

% ==========================================
% 1. CONEXIÓN AL SERVIDOR
% ==========================================

%% conectar(+Host, +Puerto)
%  Punto de entrada. Abre WebSocket y lanza el loop.
conectar(Host, Puerto) :-
    retractall(mi_jugador(_)),
    retractall(mis_cartas(_)),
    retractall(turno_actual(_)),
    retractall(estado_apuesta(_)),
    retractall(puntaje(_, _)),
    retractall(mi_ws(_)),
    retractall(ronda_actual(_)),
    retractall(partida_activa),
    assert(mis_cartas([])),
    assert(estado_apuesta(nada)),
    assert(puntaje(0, 0)),
    assert(ronda_actual(1)),
    format('~n[Jugador] Conectando a ws://~w:~w/ws ...~n', [Host, Puerto]),
    atomic_list_concat(['ws://', Host, ':', Puerto, '/ws'], URL),
    http_open_websocket(URL, WS, [subprotocols(['truco'])]),
    assert(mi_ws(WS)),
    format('[Jugador] Conectado. Esperando asignación de rol...~n'),
    loop_recepcion(WS).

%% loop_recepcion(+WS)
%  Bucle bloqueante que recibe mensajes del servidor.
loop_recepcion(WS) :-
    ws_receive(WS, Msg, [format(json)]),
    ( Msg.opcode == close ->
        format('[Jugador] Servidor cerró la conexión.~n')
    ;
        procesar_mensaje(Msg.data),
        loop_recepcion(WS)
    ).

% ==========================================
% 2. PROCESADOR DE MENSAJES ENTRANTES
% ==========================================

procesar_mensaje(Json) :-
    get_dict(tipo, Json, Tipo),
    manejar(Tipo, Json).

% -- Asignación de rol --
manejar(asignacion, Json) :-
    get_dict(jugador, Json, Rol),
    assert(mi_jugador(Rol)),
    format('~n╔══════════════════════════════╗~n'),
    format('║  Sos: ~w~n', [Rol]),
    format('╚══════════════════════════════╝~n').

% -- Sala lista: ambos jugadores conectados --
manejar(sala_lista, _) :-
    format('~n[Sistema] ¡Ambos jugadores conectados! Comienza la partida.~n').

% -- Nueva mano: el servidor reparte cartas --
manejar(nueva_mano, Json) :-
    get_dict(tus_cartas, Json, Cartas),
    get_dict(turno, Json, Turno),
    get_dict(mano, Json, Mano),
    get_dict(puntaje, Json, Pts),
    retractall(mis_cartas(_)),
    retractall(turno_actual(_)),
    retractall(estado_apuesta(_)),
    retractall(ronda_actual(_)),
    assert(mis_cartas(Cartas)),
    assert(turno_actual(Turno)),
    assert(estado_apuesta(nada)),
    assert(ronda_actual(1)),
    actualizar_puntaje(Pts),
    assert(partida_activa),
    format('~n<=============================>~n'),
    format('  NUEVA MANO — Mano: ~w~n', [Mano]),
    mostrar_puntaje,
    mostrar_mis_cartas,
    notificar_turno(Turno).

% -- Una carta fue jugada (por cualquier jugador) --
manejar(carta_jugada, Json) :-
    get_dict(jugador, Json, Quien),
    get_dict(carta, Json, Carta),
    get_dict(turno, Json, SigTurno),
    retractall(turno_actual(_)),
    assert(turno_actual(SigTurno)),
    get_dict(numero, Carta, N),
    get_dict(palo, Carta, P),
    ( mi_jugador(Quien) ->
        format('[Mesa] Tiraste: ~w de ~w~n', [N, P])
    ;
        format('[Mesa] Rival tiró: ~w de ~w~n', [N, P])
    ),
    notificar_turno(SigTurno).

% -- Resultado de la baza --
manejar(resultado_baza, Json) :-
    get_dict(ronda, Json, R),
    get_dict(ganador_baza, Json, Ganador),
    format('~n[Baza ~w] Ganó: ~w~n', [R, Ganador]),
    ( Ganador == parda ->
        format('[Baza ~w] ¡Parda! Nadie gana esta ronda.~n', [R])
    ; true ).

% -- Nueva ronda dentro de la mano --
manejar(nueva_ronda, Json) :-
    get_dict(ronda, Json, R),
    get_dict(turno, Json, Turno),
    retractall(ronda_actual(_)),
    retractall(turno_actual(_)),
    assert(ronda_actual(R)),
    assert(turno_actual(Turno)),
    format('~n--- Ronda ~w ---~n', [R]),
    mostrar_mis_cartas,
    notificar_turno(Turno).

% -- Alguien cantó (truco / respuesta) --
manejar(canto, Json) :-
    get_dict(jugador, Json, Quien),
    get_dict(canto, Json, Canto),
    get_dict(estado_apuesta, Json, NuevoEstado),
    retractall(estado_apuesta(_)),
    assert(estado_apuesta(NuevoEstado)),
    ( mi_jugador(Quien) ->
        format('[Canto] Vos cantaste: ~w~n', [Canto])
    ;
        format('[Canto] El rival cantó: ~w — Debes responder.~n', [Canto]),
        mostrar_opciones_respuesta(NuevoEstado)
    ).

% -- Fin de mano --
manejar(fin_mano, Json) :-
    get_dict(ganador, Json, Ganador),
    get_dict(puntos_ganados, Json, Pts),
    get_dict(puntaje, Json, NuevoPts),
    actualizar_puntaje(NuevoPts),
    format('~n[Fin Mano] Ganó: ~w (+~w puntos)~n', [Ganador, Pts]),
    mostrar_puntaje.

% -- Fin de partida --
manejar(fin_partida, Json) :-
    get_dict(ganador, Json, Ganador),
    get_dict(puntaje, Json, Pts),
    retractall(partida_activa),
    format('~n╔══════════════════════════════╗~n'),
    format('║      FIN DE LA PARTIDA       ║~n'),
    format('╚══════════════════════════════╝~n'),
    ( mi_jugador(Ganador) ->
        format('¡¡¡ GANASTE !!! 🏆~n')
    ;
        format('Perdiste esta vez...~n')
    ),
    get_dict(j1, Pts, P1), get_dict(j2, Pts, P2),
    format('Resultado: J1=~w | J2=~w~n', [P1, P2]).

% -- Error del servidor --
manejar(error, Json) :-
    get_dict(mensaje, Json, Msg),
    format('[ERROR] ~w~n', [Msg]).

manejar(Tipo, _) :-
    format('[Jugador] Mensaje no manejado: ~w~n', [Tipo]).

% ==========================================
% 3. ACCIONES DEL JUGADOR (API pública)
% ==========================================

%% tirar(+N)
%  Tira la carta número N (1, 2, o 3) de tu mano.
%  Ejemplo:  ?- tirar(1).
tirar(N) :-
    ( \+ partida_activa ->
        format('[Error] No hay partida activa.~n')
    ; turno_actual(T), mi_jugador(T) ->
        mi_ws(WS),
        Msg = json([tipo=jugar_carta, indice=N]),
        enviar_json(WS, Msg),
        % Actualizar cartas locales
        mis_cartas(Cartas),
        nth1(N, Cartas, CartaJugada),
        select(CartaJugada, Cartas, Restantes),
        retractall(mis_cartas(_)),
        assert(mis_cartas(Restantes))
    ;
        format('[Error] No es tu turno.~n')
    ).

%% cantar(+Canto)
%  Realiza un canto. Canto puede ser:
%    truco, retruco, vale4, quiero, no
%  Ejemplo:  ?- cantar(truco).
cantar(Canto) :-
    ( \+ partida_activa ->
        format('[Error] No hay partida activa.~n')
    ;
        mi_ws(WS),
        atom_string(Canto, CantoStr),
        Msg = json([tipo=cantar, canto=CantoStr]),
        enviar_json(WS, Msg)
    ).

%% me_voy/0
%  Abandona la mano actual (equivale a "no quiero" en la baza).
me_voy :-
    cantar(no).

% ==========================================
% 4. HELPERS DE INTERFAZ
% ==========================================

notificar_turno(Turno) :-
    ( mi_jugador(Turno) ->
        format('~n>>> ES TU TURNO <<<~n'),
        mostrar_mis_cartas,
        mostrar_cantos_disponibles
    ;
        format('[Turno] Esperando al rival...~n')
    ).

mostrar_mis_cartas :-
    mis_cartas(Cartas),
    format('~nTus cartas:~n'),
    mostrar_cartas_numeradas(Cartas, 1).

mostrar_cartas_numeradas([], _).
mostrar_cartas_numeradas([Carta|Resto], N) :-
    get_dict(numero, Carta, Num),
    get_dict(palo,   Carta, Palo),
    format('  ~w) ~w de ~w~n', [N, Num, Palo]),
    N1 is N + 1,
    mostrar_cartas_numeradas(Resto, N1).

mostrar_puntaje :-
    puntaje(P1, P2),
    format('Puntaje — J1: ~w | J2: ~w~n', [P1, P2]).

mostrar_cantos_disponibles :-
    estado_apuesta(EstAp),
    mi_jugador(Yo),
    cantos_validos(EstAp, Yo, Cantos),
    ( Cantos \= [] ->
        format('Podés cantar: ~w~n', [Cantos])
    ; true ).

mostrar_opciones_respuesta(Estado) :-
    mi_jugador(Yo),
    cantos_validos(Estado, Yo, Opts),
    format('Opciones: ~w~n', [Opts]).

%% cantos_validos(+EstadoApuesta, +MiRol, -ListaCantos)
%  Devuelve los cantos válidos según el estado actual.
cantos_validos(nada, _, [truco]).
cantos_validos(truco_propuesto(Prop), Yo, [quiero, retruco, no]) :- Yo \= Prop, !.
cantos_validos(truco_propuesto(Yo),   Yo, []).
cantos_validos(truco(_),              Yo, [retruco]).
cantos_validos(retruco_propuesto(Prop), Yo, [quiero, vale4, no]) :- Yo \= Prop, !.
cantos_validos(retruco_propuesto(Yo),   Yo, []).
cantos_validos(retruco(_),            Yo, [vale4]).
cantos_validos(vale4_propuesto(Prop), Yo, [quiero, no]) :- Yo \= Prop, !.
cantos_validos(vale4_propuesto(Yo),   Yo, []).
cantos_validos(vale4(_),              _,  []).
cantos_validos(_,                     _,  []).

actualizar_puntaje(Pts) :-
    get_dict(j1, Pts, P1),
    get_dict(j2, Pts, P2),
    retractall(puntaje(_, _)),
    assert(puntaje(P1, P2)).

% ==========================================
% 5. COMUNICACIÓN JSON
% ==========================================

enviar_json(WS, Json) :-
    with_output_to(string(Str), json_write(current_output, Json, [])),
    ws_send(WS, text(Str)).

% ==========================================
% 6. AYUDA EN CONSOLA
% ==========================================

%% ayuda/0
%  Muestra los comandos disponibles.
ayuda :-
    format('~n╔══════════════════════════════════════╗~n'),
    format('║         COMANDOS DISPONIBLES         ║~n'),
    format('╠══════════════════════════════════════╣~n'),
    format('║ conectar(Host, Puerto)               ║~n'),
    format('║   Conectar al servidor.              ║~n'),
    format('║   Ej: conectar(localhost, 8080).     ║~n'),
    format('║                                      ║~n'),
    format('║ tirar(N).                            ║~n'),
    format('║   Tirar la carta N (1, 2 o 3).       ║~n'),
    format('║                                      ║~n'),
    format('║ cantar(Canto).                       ║~n'),
    format('║   Cantos: truco, retruco, vale4,     ║~n'),
    format('║           quiero, no                 ║~n'),
    format('║                                      ║~n'),
    format('║ me_voy.                              ║~n'),
    format('║   Abandonar la mano.                 ║~n'),
    format('║                                      ║~n'),
    format('║ mostrar_mis_cartas.                  ║~n'),
    format('║   Ver tus cartas actuales.           ║~n'),
    format('║                                      ║~n'),
    format('║ mostrar_puntaje.                     ║~n'),
    format('║   Ver el marcador.                   ║~n'),
    format('╚══════════════════════════════════════╝~n').

:- format('~n[Truco Argentino — Cliente]~n').
:- format('Escribí ayuda. para ver los comandos.~n~n').
