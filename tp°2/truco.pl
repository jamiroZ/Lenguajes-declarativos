% ==========================================
% MOTOR DE TRUCO ARGENTINO (SWI-PROLOG)
% ==========================================
:- use_module(library(random)).
:- use_module(library(lists)).
:- multifile obtener_accion/2.
:- multifile enviar_evento/2.
:- multifile enviar_cartas/2.

% --- 1. JERARQUÍA Y VALORES DE LAS CARTAS ---
% valor(Carta, Poder). A mayor poder, gana la carta.
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

% --- 2. MAZO Y REPARTO ---
numero(N) :-
    member(N, [1,2,3,4,5,6,7,10,11,12]).
palo(P) :-
    member(P, [oro, copa, espada, basto]).

crear_mazo(Mazo) :-
    findall(carta(N, P), (numero(N), palo(P)), Mazo).

repartir(Mazo, CartasJ1, CartasJ2) :-
    random_permutation(Mazo, Mezclado),
    Mezclado = [
        C1,C2,C3,
        C4,C5,C6 | _
    ],
    CartasJ1 = [C1,C2,C3],
    CartasJ2 = [C4,C5,C6].

% --- 3. BUCLE PRINCIPAL DEL JUEGO ---
iniciar :-
    writeln("ARRANCO iniciar"),
    enviar_evento(
        todos,
        inicio_partida
    ),
    writeln("ANTES DE jugar"),
    jugar(0, 0, jugador1).

jugar(Pts1, Pts2, _) :-
    (   Pts1>=15
    ;   Pts2>=15
    ),
    !,
    (   Pts1 >= 15
    ->  GanadorFinal = jugador1
    ;   GanadorFinal = jugador2
    ),
    enviar_evento(
        todos,
        partida_terminada(GanadorFinal, Pts1, Pts2)
    ).


jugar(Pts1, Pts2, ManoActual) :-
    format("Entrando a jugar/3~n", []),
    crear_mazo(Mazo),
    repartir(Mazo, CartasJ1, CartasJ2),
    writeln("REPARTIO"),
    enviar_evento(
        todos,
        estado_mano(ManoActual, Pts1, Pts2)
    ),
    enviar_cartas(jugador1, CartasJ1),
    enviar_cartas(jugador2, CartasJ2), % SE ROMPE ACA (FALTA INICIAR LA MANO)
    % Iniciar la secuencia de la mano (3 rondas max)
    (   ManoActual==jugador1
    ->  mano_logica(jugador1, jugador2, CartasJ1, CartasJ2, nada, GanadorMano, EstadoFinalApuesta)
    ;   mano_logica(jugador2, jugador1, CartasJ2, CartasJ1, nada, GanadorMano, EstadoFinalApuesta)
    ),
    calcular_puntos(EstadoFinalApuesta, PuntosGanados),
    sumar_puntos(GanadorMano, PuntosGanados, Pts1, Pts2, NuevosPts1, NuevosPts2),
    enviar_evento(
        todos,
        ganador_mano(GanadorMano, PuntosGanados)
    ),
    siguiente_mano(ManoActual, ManoSig),
    writeln('SALIO DE MANO_LOGICA'),
    jugar(NuevosPts1, NuevosPts2, ManoSig).

siguiente_mano(jugador1, jugador2).
siguiente_mano(jugador2, jugador1).

sumar_puntos(jugador1, Puntos, P1, P2, NP1, P2) :-
    NP1 is P1+Puntos.
sumar_puntos(jugador2, Puntos, P1, P2, P1, NP2) :-
    NP2 is P2+Puntos.
sumar_puntos(empate, _, P1, P2, P1, P2).

% --- 4. MOTOR DE APUESTAS ---
% fase_apuesta(EstadoActual, PTurno, PRival, EstadoFinal, Resultado)
fase_apuesta(nada, PTurno, PRival, EstFin, Result) :-
    enviar_evento(
        todos,
        turno_apuesta(PTurno, [truco,nada])
    ),
    obtener_accion(
        PTurno,
        Canto
    ),  
    (
    Canto == nada
    ->
    EstFin = nada,
    Result = continuar
    ;
    Canto == truco
    ->
    enviar_evento(
        todos,
        canto_truco(PTurno)
    ),
    responder_apuesta(
        truco(PTurno),
        PRival,
        PTurno,
        EstFin,
        Result
    )
    ;
    EstFin = nada,
    Result = continuar
).

fase_apuesta(truco(Dueno), PTurno, PRival, EstFin, Result) :-
    PTurno \== Dueno,
    !,
    enviar_evento(
        todos,
        turno_retruco(PTurno, [retruco,nada])
    ),
    obtener_accion(
        PTurno,
        Canto
    ),
    (
        Canto == nada
        ->
        EstFin = truco(Dueno),
        Result = continuar
        ;
        Canto == retruco
        ->
        enviar_evento(
            todos,
            canto_retruco(PTurno)
        ),
        responder_apuesta(
            retruco(PTurno),
            PRival,
            PTurno,
            EstFin,
            Result
        )
        ;
        EstFin = truco(Dueno),
        Result = continuar
    ).

fase_apuesta(retruco(Dueno), PTurno, PRival, EstFin, Result) :-
    PTurno\==Dueno,
    !,
    enviar_evento(
        todos,
        turno_vale4(PTurno)
    ),
    obtener_accion(
        PTurno,
        Canto
    ),
    (
    Canto == nada
    ->
    EstFin = retruco(Dueno),
    Result = continuar

    ;

    Canto == vale4
    ->
    enviar_evento(
        todos,
        canto_vale4(PTurno)
    ),
    responder_apuesta(
        vale4(PTurno),
        PRival,
        PTurno,
        EstFin,
        Result
    )

    ;

    EstFin = retruco(Dueno),
    Result = continuar
).

fase_apuesta(EstadoActual, _, _, EstadoActual, continuar) :-!.

responder_apuesta(truco(PProp), PResp, PProp, EstFin, Result) :-
    enviar_evento(
        todos,
        responder_truco(PResp, [quiero,retruco,no])
    ),
    obtener_accion(
        PResp,
        Respuesta
    ),
    (   Respuesta==no
    ->  
        enviar_evento(
            todos,
            no_quiero(PResp)
        ),
        EstFin=nada,
        Result=fin(PProp)
    ;   Respuesta==quiero
    
    -> 
    enviar_evento(
        todos,
        acepto_truco(PResp)
    ), 
    EstFin=truco(PProp),
    Result=continuar
    ;   Respuesta==retruco
    ->  
        format(
        "DEBUG RETRUCO -> PResp=~w PProp=~w~n",
        [PResp,PProp]
        ),
        enviar_evento(
            todos,
            canto_retruco(PResp)
        ),
        responder_apuesta(retruco(PResp), PProp, PResp, EstFin, Result)
    ).

responder_apuesta(retruco(PProp), PResp, PProp, EstFin, Result) :-
    enviar_evento(
        todos,
        responder_retruco(PResp, [quiero,vale4,no])
    ),

    obtener_accion(
        PResp,
        Respuesta
    ),
    (   Respuesta==no
    ->  EstFin=truco(PResp),
        Result=fin(PProp)
    ;   Respuesta==quiero
    ->  EstFin=retruco(PProp),
        Result=continuar
    ;   Respuesta==vale4
    -> 
        enviar_evento(
            todos,
            canto_vale4(PResp)
        ),
        responder_apuesta(vale4(PResp), PProp, PResp, EstFin, Result)
    ).

responder_apuesta(vale4(PProp), PResp, PProp, EstFin, Result) :-

    enviar_evento(
        todos,
        responder_vale4(PResp, [quiero,no])
    ),

    obtener_accion(
        PResp,
        Respuesta
    ),

    (
        Respuesta == no
        ->
        EstFin = retruco(PResp),
        Result = fin(PProp)

        ;

        Respuesta == quiero
        ->
        EstFin = vale4(PProp),
        Result = continuar

        ;

        EstFin = retruco(PResp),
        Result = fin(PProp)
    ).

calcular_puntos(nada, 1).
calcular_puntos(truco(_), 2).
calcular_puntos(retruco(_), 3).
calcular_puntos(vale4(_), 4).

% --- 5. LÓGICA DE TURNOS Y RONDAS ---
% mano_logica: Juega 3 rondas y determina al ganador
mano_logica(PTurno, PRival, CartasT, CartasR, EstadoIn, GanadorFinal, EstadoFinalApuesta) :-
    % Ronda 1
    jugar_baza(PTurno, PRival, CartasT, CartasR, EstadoIn, EstFinR1, CartasT_R1, CartasR_R1, GanadorR1),    
    (   GanadorR1=fin(GanadorA)
    ->  GanadorFinal=GanadorA,
        EstadoFinalApuesta=EstFinR1
    ;   
        % Ronda 2
        determinar_salida(PTurno, PRival, GanadorR1, Siguiente, SiguienteRival, CartasSiguiente, CartasSiguienteRival, CartasT_R1, CartasR_R1),
        jugar_baza(Siguiente, SiguienteRival, CartasSiguiente, CartasSiguienteRival, EstFinR1, EstFinR2, CartasSiguiente_R2, CartasSiguienteRival_R2, GanadorR2),
        (   GanadorR2=fin(GanadorB)
        ->  GanadorFinal=GanadorB,
            EstadoFinalApuesta=EstFinR2
        ;   GanadorR1 == GanadorR2,
            GanadorR1 \= parda
        ->  GanadorFinal = GanadorR1,
            EstadoFinalApuesta = EstFinR2

        ;   evaluar_parda_doble(GanadorR1, GanadorR2, PTurno, PTurno, DoblePardaGanador),
            (   DoblePardaGanador\==continuar
            ->  GanadorFinal=DoblePardaGanador,
                EstadoFinalApuesta=EstFinR2
            ;   
                % Ronda 3
                determinar_salida(Siguiente, SiguienteRival, GanadorR2, Ultimo, UltimoRival, CartasUltimo, CartasUltimoRival, CartasSiguiente_R2, CartasSiguienteRival_R2),
                jugar_baza(Ultimo, UltimoRival, CartasUltimo, CartasUltimoRival, EstFinR2, EstFinR3, _, _, GanadorR3),
                (   GanadorR3=fin(GanadorC)
                ->  GanadorFinal=GanadorC,
                    EstadoFinalApuesta=EstFinR3
                ;   evaluar_ganador_final(GanadorR1, GanadorR2, GanadorR3, PTurno, GanadorFinal),
                    EstadoFinalApuesta=EstFinR3
                )
            )
        )
    ).

determinar_salida(PTurno, PRival, GanadorBazaAnterior, Siguiente, SiguienteRival, CartasSiguiente, CartasSiguienteRival, CartasT, CartasR) :-
    (   GanadorBazaAnterior==parda
    ->  Siguiente=PTurno,
        SiguienteRival=PRival,
        CartasSiguiente=CartasT,
        CartasSiguienteRival=CartasR
    ;   GanadorBazaAnterior==PTurno
    ->  Siguiente=PTurno,
        SiguienteRival=PRival,
        CartasSiguiente=CartasT,
        CartasSiguienteRival=CartasR
    ;   Siguiente=PRival,
        SiguienteRival=PTurno,
        CartasSiguiente=CartasR,
        CartasSiguienteRival=CartasT
    ).

evaluar_parda_doble(parda, parda, Mano, Mano, Mano).
evaluar_parda_doble(_, _, _, _, continuar).

evaluar_ganador_final(G1, G2, G3, Mano, Ganador) :-
    (   G1==G2,
        G1\==parda
    ->  Ganador=G1
    ;   G1==parda,
        G2\==parda
    ->  Ganador=G2
    ;   G1==parda,
        G2==parda
    ->  Ganador=Mano
    ;   G1\==parda,
        G2==parda
    ->  Ganador=G1
    ;   G3==parda
    ->  Ganador=G1
    ;   Ganador=G3
    ).

% --- 6. MECÁNICA DE CADA BAZA (TIRADA) ---
jugar_baza(PTurno, PRival, CartasT, CartasR, EstadoIn, EstadoFin, RestantesT, RestantesR, Ganador) :-
    enviar_evento(
        todos,
        estado_apuesta(EstadoIn)
    ),
    fase_apuesta(EstadoIn, PTurno, PRival, EstadoPostApuesta, ResultadoApuesta),
    (   ResultadoApuesta=fin(G)
    ->  Ganador=fin(G),
        EstadoFin=EstadoPostApuesta,
        RestantesT=CartasT,
        RestantesR=CartasR
    ;   pedir_carta(PTurno, CartasT, CartaJugadaT, RestantesT, Abandono1),
        (   Abandono1==true
        ->  Ganador=fin(PRival),
            EstadoFin=EstadoPostApuesta,
            RestantesR=CartasR
        ;   fase_apuesta(EstadoPostApuesta, PRival, PTurno, EstadoFinalBaza, ResultRival),
            (   ResultRival=fin(G2)
            ->  Ganador=fin(G2),
                EstadoFin=EstadoFinalBaza,
                RestantesR=CartasR
            ;   pedir_carta(PRival, CartasR, CartaJugadaR, RestantesR, Abandono2),
                (   Abandono2==true
                ->  Ganador=fin(PTurno),
                    EstadoFin=EstadoFinalBaza
                ;   EstadoFin=EstadoFinalBaza,
                    evaluar_tirada(CartaJugadaT, CartaJugadaR, PTurno, PRival, Ganador),
                    enviar_evento(
                        todos,
                        ganador_baza(Ganador)
                    )
                )
            )
        )
    ).

pedir_carta(Jugador, Cartas, CartaSeleccionada, CartasRestantes, Abandono) :-
    enviar_evento(
        todos,
        turno_carta(Jugador)
    ),
    enviar_cartas(
        Jugador,
        Cartas
    ),
    obtener_accion(
        Jugador,
        Input
    ),
    (
        Input == no
        ->
        Abandono = true,
        CartaSeleccionada = nula,
        CartasRestantes = Cartas

        ;
        integer(Input),
        nth1(Input, Cartas, CartaSeleccionada)
        ->
        select(
            CartaSeleccionada,
            Cartas,
            CartasRestantes
        ),

        enviar_evento(
            todos,
            carta_jugada(Jugador,CartaSeleccionada)
        ),

        Abandono = false
        ;
        Abandono = true,
        CartaSeleccionada = nula,
        CartasRestantes = Cartas
    ).

evaluar_tirada(Carta1, Carta2, P1, P2, Ganador) :-
    valor(Carta1, V1), valor(Carta2, V2),
    ( V1 > V2 -> Ganador = P1
    ; V2 > V1 -> Ganador = P2
    ; Ganador = parda
    ).

