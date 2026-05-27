% ==========================================
% TRUCO ARGENTINO - SERVIDOR WEBSOCKET
% SWI-Prolog
%
% DEPENDENCIAS:
%   :- use_module(library(http/websocket)).
%   :- use_module(library(http/thread_httpd)).
%   :- use_module(library(http/http_dispatch)).
%
% USO:
%   $ swipl truco_server.pl
%   ?- iniciar_servidor(8080).
%
% Luego abrir truco_client.html en DOS pestañas del navegador.
% ==========================================

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/websocket)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_files)).
:- use_module(library(random)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(option)).

% ==========================================
% ESTADO GLOBAL DEL JUEGO (usando assert/retract)
% ==========================================

% estado_juego(PuntosJ1, PuntosJ2, ManoActual, Fase, EstadoApuesta,
%              CartasJ1, CartasJ2, BazasGanadas, RondaActual,
%              TurnoActual, CartasJugadasBaza)
:- dynamic estado_juego/11.

% conexion(Jugador, WebSocket)  -- jugador = jugador1 | jugador2
:- dynamic conexion/2.

% sala_lista/0 -- true cuando ambos jugadores están conectados
:- dynamic sala_lista/0.

% ==========================================
% 1. JERARQUÍA Y VALORES (sin cambios del original)
% ==========================================

valor(carta(1, espada), 14).
valor(carta(1, basto),  13).
valor(carta(7, espada), 12).
valor(carta(7, oro),    11).
valor(carta(3, _),      10).
valor(carta(2, _),       9).
valor(carta(1, copa),    8).
valor(carta(1, oro),     8).
valor(carta(12, _),      7).
valor(carta(11, _),      6).
valor(carta(10, _),      5).
valor(carta(7, copa),    4).
valor(carta(7, basto),   4).
valor(carta(6, _),       3).
valor(carta(5, _),       2).
valor(carta(4, _),       1).

% ==========================================
% 2. MAZO Y REPARTO
% ==========================================

numero(N) :- member(N, [1,2,3,4,5,6,7,10,11,12]).
palo(P)   :- member(P, [oro, copa, espada, basto]).

crear_mazo(Mazo) :-
    findall(carta(N,P), (numero(N), palo(P)), Mazo).

repartir(Mazo, CartasJ1, CartasJ2) :-
    random_permutation(Mazo, Mezclado),
    length(CartasJ1, 3),
    length(CartasJ2, 3),
    append(CartasJ1, CartasJ2, Seis),
    append(Seis, _, Mezclado).

% ==========================================
% 3. SERVIDOR HTTP / WEBSOCKET
% ==========================================

:- http_handler(root(ws),   manejar_ws,     []).
:- http_handler(root(.),    manejar_static, [prefix]).

%% iniciar_servidor(+Puerto)
%  Punto de entrada principal.
iniciar_servidor(Puerto) :-
    retractall(estado_juego(_,_,_,_,_,_,_,_,_,_,_)),
    retractall(conexion(_,_)),
    retractall(sala_lista),
    http_server(http_dispatch, [port(Puerto)]),
    format('[Servidor] Escuchando en http://localhost:~w~n', [Puerto]),
    format('[Servidor] Esperando 2 jugadores...~n').

manejar_static(Request) :-
    http_reply_from_files('.', [], Request).

%% manejar_ws(+Request)
%  Upgrade HTTP → WebSocket; asigna rol al jugador.
manejar_ws(Request) :-
    http_upgrade_to_websocket(atender_jugador, [subprotocols(['truco'])], Request).

atender_jugador(WebSocket) :-
    asignar_jugador(WebSocket, Jugador),
    format('[Servidor] ~w conectado.~n', [Jugador]),
    enviar_json(WebSocket, json([tipo=asignacion, jugador=Jugador])),
    ( \+ sala_lista, conexion(jugador1, _), conexion(jugador2, _) ->
        assert(sala_lista),
        broadcast_json(json([tipo=sala_lista])),
        nueva_mano
    ; true ),
    loop_ws(Jugador, WebSocket).

asignar_jugador(WebSocket, Jugador) :-
    ( \+ conexion(jugador1, _) ->
        Jugador = jugador1,
        assert(conexion(jugador1, WebSocket))
    ; \+ conexion(jugador2, _) ->
        Jugador = jugador2,
        assert(conexion(jugador2, WebSocket))
    ;
        Jugador = espectador
    ).

% ==========================================
% 4. LOOP PRINCIPAL DE MENSAJES
% ==========================================

loop_ws(Jugador, WebSocket) :-
    ws_receive(WebSocket, Mensaje, [format(json)]),
    ( Mensaje.opcode == close ->
        format('[Servidor] ~w desconectado.~n', [Jugador]),
        retract(conexion(Jugador, WebSocket))
    ;
        DatosJson = Mensaje.data,
        procesar_mensaje(Jugador, DatosJson),
        loop_ws(Jugador, WebSocket)
    ).

% ==========================================
% 5. PROCESADOR DE MENSAJES ENTRANTES
% ==========================================

procesar_mensaje(Jugador, Json) :-
    get_dict(tipo, Json, Tipo),
    procesar_tipo(Tipo, Jugador, Json).

% -- El jugador tira una carta --
procesar_tipo(jugar_carta, Jugador, Json) :-
    get_dict(indice, Json, Idx),
    manejar_tirada(Jugador, Idx).

% -- El jugador canta (truco / retruco / vale4 / quiero / no) --
procesar_tipo(cantar, Jugador, Json) :-
    get_dict(canto, Json, Canto),
    manejar_canto(Jugador, Canto).

% -- El jugador pide el estado (reconexión) --
procesar_tipo(pedir_estado, Jugador, _) :-
    ws_jugador(Jugador, WS),
    enviar_estado_completo(WS).

procesar_tipo(Otro, Jugador, _) :-
    format('[Servidor] Mensaje desconocido: ~w de ~w~n', [Otro, Jugador]).

% ==========================================
% 6. LÓGICA DEL JUEGO (adaptada para red)
% ==========================================

nueva_mano :-
    estado_juego(Pts1, Pts2, ManoAnterior, _, _, _, _, _, _, _, _),
    !,
    siguiente_mano(ManoAnterior, ManoNueva),
    iniciar_mano(ManoNueva, Pts1, Pts2).
nueva_mano :-
    % primera mano de la partida
    iniciar_mano(jugador1, 0, 0).

iniciar_mano(Mano, Pts1, Pts2) :-
    crear_mazo(Mazo),
    repartir(Mazo, C1, C2),
    retractall(estado_juego(_,_,_,_,_,_,_,_,_,_,_)),
    % Bazas = [GanadorRonda1, GanadorRonda2, GanadorRonda3]  (se va llenando)
    assert(estado_juego(
        Pts1, Pts2,          % puntos
        Mano,                % quién tiene la mano (sale primero)
        esperando_tirada,    % fase: esperando_tirada | esperando_respuesta_canto
        nada,                % estado apuesta actual
        C1, C2,              % cartas restantes de cada jugador
        [],                  % bazas ganadas [g1, g2, g3]
        1,                   % ronda actual (1-3)
        Mano,                % turno actual
        []                   % cartas ya jugadas en baza actual [carta_j1, carta_j2]
    )),
    % Notificar a ambos jugadores
    cartas_a_json(C1, CJ1),
    cartas_a_json(C2, CJ2),
    ws_jugador(jugador1, WS1),
    ws_jugador(jugador2, WS2),
    enviar_json(WS1, json([
        tipo=nueva_mano,
        mano=Mano,
        puntaje=json([j1=Pts1, j2=Pts2]),
        tus_cartas=CJ1,
        turno=Mano
    ])),
    enviar_json(WS2, json([
        tipo=nueva_mano,
        mano=Mano,
        puntaje=json([j1=Pts1, j2=Pts2]),
        tus_cartas=CJ2,
        turno=Mano
    ])),
    format('[Servidor] Nueva mano. Mano=~w Pts=~w/~w~n', [Mano, Pts1, Pts2]).

% ---- TIRADA DE CARTA ----

manejar_tirada(Jugador, Idx) :-
    estado_juego(P1, P2, Mano, Fase, EstAp, C1, C2, Bazas, Ronda, Turno, Jugadas),
    ( Fase \= esperando_tirada ->
        ws_jugador(Jugador, WS),
        enviar_error(WS, "No es momento de tirar carta")
    ; Turno \= Jugador ->
        ws_jugador(Jugador, WS),
        enviar_error(WS, "No es tu turno")
    ;
        cartas_de(Jugador, C1, C2, Cartas),
        nth1(Idx, Cartas, CartaJugada),
        select(CartaJugada, Cartas, CartasRest),
        actualizar_cartas(Jugador, CartasRest, C1, C2, NuevasC1, NuevasC2),
        NuevasJugadas = [carta_de(Jugador, CartaJugada) | Jugadas],
        % ¿Ya jugaron los dos?
        length(NuevasJugadas, NJ),
        ( NJ =:= 2 ->
            % resolver la baza
            resolver_baza(Jugador, NuevasJugadas, P1, P2, Mano, EstAp, NuevasC1, NuevasC2, Bazas, Ronda)
        ;
            % el rival debe jugar
            rival_de(Jugador, Rival),
            retractall(estado_juego(_,_,_,_,_,_,_,_,_,_,_)),
            assert(estado_juego(P1, P2, Mano, esperando_tirada, EstAp, NuevasC1, NuevasC2, Bazas, Ronda, Rival, NuevasJugadas)),
            carta_a_json(CartaJugada, CJ),
            broadcast_json(json([
                tipo=carta_jugada,
                jugador=Jugador,
                carta=CJ,
                turno=Rival
            ]))
        )
    ).

resolver_baza(UltimoJugador, Jugadas, P1, P2, Mano, EstAp, C1, C2, BazasPrev, Ronda) :-
    % Extraer las dos cartas
    member(carta_de(jugador1, Carta1), Jugadas),
    member(carta_de(jugador2, Carta2), Jugadas),
    evaluar_tirada(Carta1, Carta2, jugador1, jugador2, GanadorBaza),
    NuevasBazas = [GanadorBaza | BazasPrev],
    % Notificar resultado de baza
    carta_a_json(Carta1, CJ1),
    carta_a_json(Carta2, CJ2),
    broadcast_json(json([
        tipo=resultado_baza,
        ronda=Ronda,
        carta_j1=CJ1,
        carta_j2=CJ2,
        ganador_baza=GanadorBaza
    ])),
    % ¿Hay ganador de la mano?
    SigRonda is Ronda + 1,
    ( verificar_ganador_mano(NuevasBazas, Mano, GanadorMano) ->
        finalizar_mano(GanadorMano, EstAp, P1, P2, Mano)
    ; SigRonda > 3 ->
        % Todas las rondas jugadas: desempate por bazas
        evaluar_ganador_final_lista(NuevasBazas, Mano, GanadorFinal),
        finalizar_mano(GanadorFinal, EstAp, P1, P2, Mano)
    ;
        % Continuar con ronda siguiente
        siguiente_turno_baza(GanadorBaza, Mano, jugador1, jugador2, SigTurno),
        retractall(estado_juego(_,_,_,_,_,_,_,_,_,_,_)),
        assert(estado_juego(P1, P2, Mano, esperando_tirada, EstAp, C1, C2, NuevasBazas, SigRonda, SigTurno, [])),
        broadcast_json(json([
            tipo=nueva_ronda,
            ronda=SigRonda,
            turno=SigTurno
        ]))
    ).

siguiente_turno_baza(parda, Mano, _, _, Mano).
siguiente_turno_baza(jugador1, _, jugador1, _, jugador1).
siguiente_turno_baza(jugador2, _, _, jugador2, jugador2).

% ---- CANTOS (TRUCO / RETRUCO / VALE4) ----

manejar_canto(Jugador, Canto) :-
    estado_juego(P1, P2, Mano, Fase, EstAp, C1, C2, Bazas, Ronda, Turno, Jugadas),
    procesar_canto(Jugador, Canto, EstAp, NuevoEstAp, Resultado),
    ( Resultado = error(Msg) ->
        ws_jugador(Jugador, WS),
        enviar_error(WS, Msg)
    ; Resultado = fin(Ganador) ->
        finalizar_mano(Ganador, NuevoEstAp, P1, P2, Mano)
    ;
        rival_de(Jugador, Rival),
        retractall(estado_juego(_,_,_,_,_,_,_,_,_,_,_)),
        assert(estado_juego(P1, P2, Mano, Fase, NuevoEstAp, C1, C2, Bazas, Ronda, Turno, Jugadas)),
        broadcast_json(json([
            tipo=canto,
            jugador=Jugador,
            canto=Canto,
            estado_apuesta=NuevoEstAp,
            aguarda_respuesta=Rival
        ]))
    ).

% --- Reglas de canto válidas ---
% Propuesta de truco
procesar_canto(Jugador, truco, nada, truco_propuesto(Jugador), continuar) :- !.
% Respuesta al truco
procesar_canto(Jugador, quiero, truco_propuesto(Prop), truco(Prop), continuar) :-
    Jugador \= Prop, !.
procesar_canto(Jugador, no, truco_propuesto(Prop), nada, fin(Prop)) :-
    Jugador \= Prop, !.
procesar_canto(Jugador, retruco, truco_propuesto(Prop), retruco_propuesto(Jugador), continuar) :-
    Jugador \= Prop, !.
% Respuesta al retruco
procesar_canto(Jugador, quiero, retruco_propuesto(Prop), retruco(Prop), continuar) :-
    Jugador \= Prop, !.
procesar_canto(Jugador, no, retruco_propuesto(Prop), truco(Jugador), fin(Prop)) :-
    Jugador \= Prop, !.
procesar_canto(Jugador, vale4, retruco_propuesto(Prop), vale4_propuesto(Jugador), continuar) :-
    Jugador \= Prop, !.
% Respuesta al vale4
procesar_canto(Jugador, quiero, vale4_propuesto(Prop), vale4(Prop), continuar) :-
    Jugador \= Prop, !.
procesar_canto(Jugador, no, vale4_propuesto(Prop), retruco(Jugador), fin(Prop)) :-
    Jugador \= Prop, !.

procesar_canto(_, _, _, _, error("Canto inválido en este estado")).

% ---- RESOLUCIÓN DE LA MANO ----

finalizar_mano(GanadorMano, EstadoApuesta, P1, P2, ManoActual) :-
    calcular_puntos(EstadoApuesta, Pts),
    sumar_puntos(GanadorMano, Pts, P1, P2, NP1, NP2),
    broadcast_json(json([
        tipo=fin_mano,
        ganador=GanadorMano,
        puntos_ganados=Pts,
        puntaje=json([j1=NP1, j2=NP2])
    ])),
    format('[Servidor] Mano terminada. Ganador=~w +~w pts. Total: ~w/~w~n',
           [GanadorMano, Pts, NP1, NP2]),
    ( NP1 >= 15 ->
        broadcast_json(json([tipo=fin_partida, ganador=jugador1, puntaje=json([j1=NP1, j2=NP2])])),
        retractall(estado_juego(_,_,_,_,_,_,_,_,_,_,_))
    ; NP2 >= 15 ->
        broadcast_json(json([tipo=fin_partida, ganador=jugador2, puntaje=json([j1=NP1, j2=NP2])])),
        retractall(estado_juego(_,_,_,_,_,_,_,_,_,_,_))
    ;
        % Preparar siguiente mano con pequeño delay
        sleep(2),
        siguiente_mano(ManoActual, SigMano),
        crear_mazo(Mazo2),
        repartir(Mazo2, NC1, NC2),
        retractall(estado_juego(_,_,_,_,_,_,_,_,_,_,_)),
        assert(estado_juego(NP1, NP2, SigMano, dummy, dummy, [], [], [], 0, dummy, [])),
        iniciar_mano(SigMano, NP1, NP2)
    ).

% ==========================================
% 7. LÓGICA DE EVALUACIÓN (del original)
% ==========================================

evaluar_tirada(C1, C2, P1, P2, Ganador) :-
    valor(C1, V1), valor(C2, V2),
    ( V1 > V2 -> Ganador = P1
    ; V2 > V1 -> Ganador = P2
    ; Ganador = parda
    ).

% Verifica si con las bazas actuales ya hay un ganador definitivo
verificar_ganador_mano(Bazas, Mano, Ganador) :-
    length(Bazas, NB),
    ( NB >= 2 ->
        evaluar_ganador_parcial(Bazas, Mano, Ganador)
    ;
        fail
    ).

evaluar_ganador_parcial([G2, G1], Mano, Ganador) :-  % Bazas en orden inverso (lista)
    ( G1 == G2, G1 \= parda -> Ganador = G1
    ; G1 \= parda, G2 == parda -> Ganador = G1
    ; G1 == parda, G2 \= parda -> Ganador = G2
    ; fail
    ).
evaluar_ganador_parcial(_, _, _) :- fail.

evaluar_ganador_final_lista(Bazas, Mano, Ganador) :-
    % Bazas = [R3, R2, R1] (orden inverso)
    ( Bazas = [G3, G2, G1] ->
        evaluar_ganador_final(G1, G2, G3, Mano, Ganador)
    ; Bazas = [G2, G1] ->
        evaluar_ganador_final(G1, G2, parda, Mano, Ganador)
    ; Bazas = [G1] ->
        ( G1 = parda -> Ganador = Mano ; Ganador = G1 )
    ;
        Ganador = Mano
    ).

evaluar_ganador_final(G1, G2, G3, Mano, Ganador) :-
    ( G1 == G2, G1 \= parda -> Ganador = G1
    ; G1 == parda, G2 \= parda -> Ganador = G2
    ; G1 == parda, G2 == parda -> Ganador = Mano
    ; G1 \= parda, G2 == parda -> Ganador = G1
    ; G3 == parda -> Ganador = G1
    ; Ganador = G3
    ).

calcular_puntos(nada, 1).
calcular_puntos(truco_propuesto(_), 1).
calcular_puntos(truco(_), 2).
calcular_puntos(retruco_propuesto(_), 2).
calcular_puntos(retruco(_), 3).
calcular_puntos(vale4_propuesto(_), 3).
calcular_puntos(vale4(_), 4).

% ==========================================
% 8. UTILIDADES
% ==========================================

siguiente_mano(jugador1, jugador2).
siguiente_mano(jugador2, jugador1).

sumar_puntos(jugador1, Pts, P1, P2, NP1, P2) :- NP1 is P1 + Pts.
sumar_puntos(jugador2, Pts, P1, P2, P1, NP2) :- NP2 is P2 + Pts.
sumar_puntos(parda,    _,  P1, P2, P1, P2).
sumar_puntos(empate,   _,  P1, P2, P1, P2).

rival_de(jugador1, jugador2).
rival_de(jugador2, jugador1).

cartas_de(jugador1, C1, _, C1).
cartas_de(jugador2, _, C2, C2).

actualizar_cartas(jugador1, Rest, _, C2, Rest, C2).
actualizar_cartas(jugador2, Rest, C1, _, C1, Rest).

ws_jugador(Jugador, WS) :-
    conexion(Jugador, WS).

carta_a_json(carta(N, P), json([numero=N, palo=P])).

cartas_a_json(Cartas, Json) :-
    maplist(carta_a_json, Cartas, Json).

enviar_json(WS, Json) :-
    with_output_to(string(Str), json_write(current_output, Json, [])),
    ws_send(WS, text(Str)).

enviar_error(WS, Msg) :-
    enviar_json(WS, json([tipo=error, mensaje=Msg])).

broadcast_json(Json) :-
    with_output_to(string(Str), json_write(current_output, Json, [])),
    ( conexion(jugador1, WS1) -> ws_send(WS1, text(Str)) ; true ),
    ( conexion(jugador2, WS2) -> ws_send(WS2, text(Str)) ; true ).

enviar_estado_completo(WS) :-
    ( estado_juego(P1, P2, Mano, Fase, EstAp, C1, C2, Bazas, Ronda, Turno, Jugadas) ->
        cartas_a_json(C1, CJ1), cartas_a_json(C2, CJ2),
        enviar_json(WS, json([
            tipo=estado,
            puntaje=json([j1=P1, j2=P2]),
            mano=Mano,
            fase=Fase,
            estado_apuesta=EstAp,
            cartas_j1=CJ1,
            cartas_j2=CJ2,
            ronda=Ronda,
            turno=Turno
        ]))
    ; true ).
