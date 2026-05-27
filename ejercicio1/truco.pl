% ==========================================
% truco.pl
% MOTOR DE TRUCO (SOLO LOGICA)
% ==========================================

:- use_module(library(random)).
:- use_module(library(lists)).

% ==========================================
% PREDICADOS QUE IMPLEMENTA server.pl
% ==========================================

:- multifile pedir_accion/3.
:- multifile mostrar_mensaje/2.
:- multifile mostrar_cartas_ws/2.

% ==========================================
% 1. JERARQUIA Y VALORES
% ==========================================

valor(carta(1, espada), 14).
valor(carta(1, basto), 13).
valor(carta(7, espada), 12).
valor(carta(7, oro), 11).
valor(carta(3, _), 10).
valor(carta(2, _), 9).
valor(carta(1, copa), 8).
valor(carta(1, oro), 8).
valor(carta(12, _), 7).
valor(carta(11, _), 6).
valor(carta(10, _), 5).
valor(carta(7, copa), 4).
valor(carta(7, basto), 4).
valor(carta(6, _), 3).
valor(carta(5, _), 2).
valor(carta(4, _), 1).

% ==========================================
% 2. MAZO
% ==========================================

numero(N) :-
    member(N, [1,2,3,4,5,6,7,10,11,12]).

palo(P) :-
    member(P, [oro, copa, espada, basto]).

crear_mazo(Mazo) :-
    findall(carta(N, P), (numero(N), palo(P)), Mazo).

repartir(Mazo, CartasJ1, CartasJ2) :-
    random_permutation(Mazo, MazoMezclado),
    length(CartasJ1, 3),
    length(CartasJ2, 3),
    append(CartasJ1, CartasJ2, SeisCartas),
    append(SeisCartas, _, MazoMezclado).

% ==========================================
% 3. JUEGO
% ==========================================

iniciar :-
    jugar(0,0,jugador1).

jugar(P1, P2, _) :-
    (P1 >= 15 ; P2 >= 15),
    !,
    mostrar_mensaje(jugador1, 'PARTIDA TERMINADA'),
    mostrar_mensaje(jugador2, 'PARTIDA TERMINADA').

jugar(P1, P2, ManoActual) :-

    crear_mazo(Mazo),
    repartir(Mazo, CartasJ1, CartasJ2),

    mostrar_cartas_ws(jugador1, CartasJ1),
    mostrar_cartas_ws(jugador2, CartasJ2),

    ( ManoActual == jugador1 ->
        mano_logica(
            jugador1,
            jugador2,
            CartasJ1,
            CartasJ2,
            nada,
            Ganador,
            EstadoFinal
        )
    ;
        mano_logica(
            jugador2,
            jugador1,
            CartasJ2,
            CartasJ1,
            nada,
            Ganador,
            EstadoFinal
        )
    ),

    calcular_puntos(EstadoFinal, Puntos),

    sumar_puntos(
        Ganador,
        Puntos,
        P1,
        P2,
        NP1,
        NP2
    ),
    format(string(TextoMano),
       'Ganador mano: ~w (+~w puntos)',
       [GanadorMano, PuntosGanados]),

    mostrar_mensaje(jugador1, TextoMano),
    mostrar_mensaje(jugador2, TextoMano),
    format(string(TextoPts),
       'Puntaje -> J1: ~w | J2: ~w',
       [NuevosPts1, NuevosPts2]),

    mostrar_mensaje(jugador1, TextoPts),
    mostrar_mensaje(jugador2, TextoPts),
    siguiente_mano(ManoActual, ManoSig),

    jugar(NP1, NP2, ManoSig).

siguiente_mano(jugador1, jugador2).
siguiente_mano(jugador2, jugador1).

sumar_puntos(jugador1, P, P1, P2, NP1, P2) :-
    NP1 is P1 + P.

sumar_puntos(jugador2, P, P1, P2, P1, NP2) :-
    NP2 is P2 + P.

sumar_puntos(empate, _, P1, P2, P1, P2).

% ==========================================
% 4. APUESTAS
% ==========================================

fase_apuesta(nada, PTurno, PRival, EstFin, Result) :-

    pedir_accion(PTurno, 'truco/nada', Canto),

    ( Canto == nada ->
        EstFin = nada,
        Result = continuar

    ; Canto == truco ->
        responder_apuesta(
            truco(PTurno),
            PRival,
            PTurno,
            EstFin,
            Result
        )
    ).

fase_apuesta(EstadoActual, _, _, EstadoActual, continuar).

responder_apuesta(
    truco(PProp),
    PResp,
    PProp,
    EstFin,
    Result
) :-

    pedir_accion(
        PResp,
        'quiero/retruco/no',
        Respuesta
    ),

    ( Respuesta == no ->
        EstFin = nada,
        Result = fin(PProp)

    ; Respuesta == quiero ->
        EstFin = truco(PProp),
        Result = continuar

    ; Respuesta == retruco ->
        EstFin = retruco(PResp),
        Result = continuar
    ).

calcular_puntos(nada, 1).
calcular_puntos(truco(_), 2).
calcular_puntos(retruco(_), 3).
calcular_puntos(vale4(_), 4).

% ==========================================
% 5. LOGICA MANO
% ==========================================

mano_logica(
    PTurno,
    PRival,
    CartasT,
    CartasR,
    EstadoIn,
    GanadorFinal,
    EstadoFinalApuesta
) :-

    jugar_baza(
        PTurno,
        PRival,
        CartasT,
        CartasR,
        EstadoIn,
        EstadoFinalApuesta,
        _,
        _,
        GanadorFinal
    ).

% ==========================================
% 6. BAZAS
% ==========================================

jugar_baza(
    PTurno,
    PRival,
    CartasT,
    CartasR,
    EstadoIn,
    EstadoFin,
    RestantesT,
    RestantesR,
    Ganador
) :-

    fase_apuesta(
        EstadoIn,
        PTurno,
        PRival,
        EstadoPostApuesta,
        ResultadoApuesta
    ),

    ( ResultadoApuesta = fin(G) ->

        Ganador = G,
        EstadoFin = EstadoPostApuesta

    ;

        pedir_carta(
            PTurno,
            CartasT,
            CartaT,
            RestantesT
        ),

        pedir_carta(
            PRival,
            CartasR,
            CartaR,
            RestantesR
        ),

        evaluar_tirada(
            CartaT,
            CartaR,
            PTurno,
            PRival,
            Ganador
        ),
        term_string(CartaJugadaT, CT),
        term_string(CartaJugadaR, CR),

        atomic_list_concat([
            'Baza: ',
            PTurno,
            ' jugo ',
            CT,
            ' | ',
            PRival,
            ' jugo ',
            CR,
            ' | Ganador: ',
            Ganador
        ], TextoBaza),

        mostrar_mensaje(jugador1, TextoBaza),
        mostrar_mensaje(jugador2, TextoBaza).
        EstadoFin = EstadoPostApuesta
    ).

pedir_carta(
    Jugador,
    Cartas,
    CartaSeleccionada,
    CartasRestantes
) :-

    term_string(Cartas, Texto),

    mostrar_mensaje(
        Jugador,
        Texto
    ),

    pedir_accion(
        Jugador,
        'indice_carta',
        Input
    ),

    nth1(Input, Cartas, CartaSeleccionada),

    select(
        CartaSeleccionada,
        Cartas,
        CartasRestantes
    ).

evaluar_tirada(
    Carta1,
    Carta2,
    P1,
    P2,
    Ganador
) :-

    valor(Carta1, V1),
    valor(Carta2, V2),

    ( V1 > V2 ->
        Ganador = P1

    ; V2 > V1 ->
        Ganador = P2

    ; Ganador = parda
    ).

 mostrar_cartas(Jugador, Cartas) :- mostrar_cartas_ws(Jugador, Cartas).
 mostrar_cartas_ws(Jugador, Cartas) :-

    maplist(carta_string, Cartas, Lista),

    atomic_list_concat(Lista, ' | ', Texto),

    format(string(Msg),
           'Tus cartas: ~w',
           [Texto]),

    enviar_mensaje(Jugador, Msg).