% ====================================================================
% truco2.pl - TRUCO ARGENTINO CON ESTADOS Y DCG
% ====================================================================
% Representa la partida con el termino estado/5 y encadena las
% transiciones mediante reglas DCG (-->), leyendo el estado con
% estado/3 y escribiendolo con nuevo_estado/3.
% ====================================================================
:- use_module(library(random)).
:- use_module(library(lists)).
:- multifile obtener_accion/2.
:- multifile enviar_evento/2.
:- multifile enviar_cartas/2.

% ====================================================================
% 1. CARTAS
% ====================================================================
valor(carta(1,espada),14). valor(carta(1,basto),13).
valor(carta(7,espada),12). valor(carta(7,oro),11).
valor(carta(3,_),10). valor(carta(2,_),9).
valor(carta(1,copa),8).  valor(carta(1,oro),8).
valor(carta(12,_),7).    valor(carta(11,_),6).
valor(carta(10,_),5).    valor(carta(7,copa),4).
valor(carta(7,basto),4). valor(carta(6,_),3).
valor(carta(5,_),2).     valor(carta(4,_),1).

numero(N):-member(N,[1,2,3,4,5,6,7,10,11,12]).
palo(P):-member(P,[oro,copa,espada,basto]).
crear_mazo(M):-findall(carta(N,P),(numero(N),palo(P)),M).
repartir(M,C1,C2):-random_permutation(M,[A,B,C,D,E,F|_]),C1=[A,B,C],C2=[D,E,F].

% ====================================================================
% 2. ESTADO
% ====================================================================
% estado(Puntos, Mano, Cartas, Apuesta, Bazas)
%   Puntos = puntos(P1,P2)
%   Mano   = jugador que es mano
%   Cartas = cartas(C1,C2)
%   Apuesta = nada|truco(Q)|retruco(Q)|vale4(Q)
%   Bazas  = [G1,G2,G3]  ganadores baza 1,2,3

% ====================================================================
% 3. PREDICADOS DCG: leer/escribir estado
% ====================================================================
estado(S,[S|T],T).
nuevo_estado(S,_,[S]).

% ====================================================================
% 4. ENTRADA
% ====================================================================
iniciar(J1,J2):-
    enviar_evento(todos,inicio_partida),
    phrase(bucle_principal(J1,J2),[estado(puntos(0,0),J1,cartas([],[]),nada,[])],_).

% ====================================================================
% 5. BUCLE PRINCIPAL (DCG)
% ====================================================================
bucle_principal(J1,J2)-->
    estado(estado(puntos(P1,P2),_,_,_,_)),
    {(P1>=15;P2>=15)},!,
    {(P1>=15->G=J1;G=J2),enviar_evento(todos,partida_terminada(G,P1,P2))}.
bucle_principal(J1,J2)-->
    fase_reparto(J1,J2),
    estado(E0),
    {jugar_mano(E0,J1,J2,E)},
    nuevo_estado(E),
    bucle_principal(J1,J2).

% ====================================================================
% 6. REPARTO (DCG)
% ====================================================================
fase_reparto(J1,J2)-->
    estado(estado(puntos(P1,P2),M,_,A,_)),
    {crear_mazo(Mazo),repartir(Mazo,C1,C2),
     enviar_evento(todos,estado_mano(M,P1,P2)),
     enviar_cartas(J1,C1),enviar_cartas(J2,C2)},
    nuevo_estado(estado(puntos(P1,P2),M,cartas(C1,C2),A,[])).

% ====================================================================
% 7. MANO (predicado regular, transforma estado)
% ====================================================================
jugar_mano(estado(puntos(P1,P2),M,cartas(C1,C2),_,_),J1,J2,
           estado(puntos(NP1,NP2),M1,cartas(C1,C2),nada,[])):-
    (M==J1->PT=J1,PR=J2,CT=C1,CR=C2;PT=J2,PR=J1,CT=C2,CR=C1),
    jugar_bazas(PT,PR,CT,CR,nada,[],PT,GanadorMano,ApuestaFinal,_,_),
    calcular_puntos(ApuestaFinal,Ptos),
    sumar_puntos(GanadorMano,J1,J2,Ptos,P1,P2,NP1,NP2),
    enviar_evento(todos,ganador_mano(GanadorMano,Ptos)),
    cambiar_mano(M,J1,J2,M1).

% ====================================================================
% 8. SECUENCIA DE BAZAS (predicado regular)
% ====================================================================
% 2 bazas: mismo ganador no-parda -> mano terminada
jugar_bazas(_,_,_,_,A,[G1,G2],_,G,A,_,_):-G1\=parda,G1==G2,!,G=G1.
% 2 bazas: ambos parda -> gana quien es mano
jugar_bazas(_,_,_,_,A,[parda,parda],Mano,G,A,_,_):-!,G=Mano.
% 3 bazas: evaluar ganador final
jugar_bazas(_,_,_,_,A,[G1,G2,G3],Mano,G,A,_,_):-
    evaluar_ganador_final([G1,G2,G3],Mano,G).
% General: jugar una baza y continuar
jugar_bazas(PT,PR,CT,CR,A,Bs,Mano,G,Aout,CTf,CRf):-
    jugar_baza(PT,PR,CT,CR,A,Am,CT1,CR1,R),
    (R=fin(G)->Aout=Am,CTf=CT1,CRf=CR1
    ;append(Bs,[R],Bs1),
     determinar_saliente(PT,PR,R,PT2,PR2,CT2,CR2,CT1,CR1),
     jugar_bazas(PT2,PR2,CT2,CR2,Am,Bs1,Mano,G,Aout,CTf,CRf)
    ).

% ====================================================================
% 9. BAZA INDIVIDUAL (predicado regular)
% ====================================================================
jugar_baza(PT,PR,CT,CR,EA,EF,CT1,CR1,R):-
    enviar_evento(todos,estado_apuesta(EA)),
    fase_apuesta(EA,PT,PR,EP,R1),
    (R1=fin(G)->R=fin(G),EF=EP,CT1=CT,CR1=CR
    ;pedir_carta(PT,CT,CJT,CT1,Ab1),
     (Ab1=true->R=fin(PR),EF=EP,CR1=CR
     ;fase_apuesta(EP,PR,PT,EFB,R2),
      (R2=fin(G2)->R=fin(G2),EF=EFB,CR1=CR
      ;pedir_carta(PR,CR,CJR,CR1,Ab2),
       (Ab2=true->R=fin(PT),EF=EFB
       ;EF=EFB,
        evaluar_tirada(CJT,CJR,PT,PR,R),
        enviar_evento(todos,ganador_baza(R))
       )
      )
     )
    ).

% ====================================================================
% 10. APUESTAS
% ====================================================================
fase_apuesta(nada,PT,PR,EF,R):-
    enviar_evento(todos,turno_apuesta(PT,[truco,nada])),
    obtener_accion(PT,Canto),
    (Canto==truco->
     enviar_evento(todos,canto_truco(PT)),
     responder_apuesta(truco(PT),PR,PT,EF,R)
    ;EF=nada,R=continuar).

fase_apuesta(truco(D),PT,PR,EF,R):-
    PT\==D,!,
    enviar_evento(todos,turno_retruco(PT,[retruco,nada])),
    obtener_accion(PT,Canto),
    (Canto==retruco->
     enviar_evento(todos,canto_retruco(PT)),
     responder_apuesta(retruco(PT),PR,PT,EF,R)
    ;EF=truco(D),R=continuar).

fase_apuesta(retruco(D),PT,PR,EF,R):-
    PT\==D,!,
    enviar_evento(todos,turno_vale4(PT)),
    obtener_accion(PT,Canto),
    (Canto==vale4->
     enviar_evento(todos,canto_vale4(PT)),
     responder_apuesta(vale4(PT),PR,PT,EF,R)
    ;EF=retruco(D),R=continuar).

fase_apuesta(E,_,_,E,continuar).

responder_apuesta(truco(P),PResp,P,EF,R):-
    enviar_evento(todos,responder_truco(PResp,[quiero,retruco,no])),
    obtener_accion(PResp,Resp),
    (Resp=no->enviar_evento(todos,no_quiero(PResp)),EF=nada,R=fin(P)
    ;Resp=quiero->enviar_evento(todos,acepto_truco(PResp)),EF=truco(P),R=continuar
    ;Resp=retruco->enviar_evento(todos,canto_retruco(PResp)),
                   responder_apuesta(retruco(PResp),P,PResp,EF,R)
    ).

responder_apuesta(retruco(P),PResp,P,EF,R):-
    enviar_evento(todos,responder_retruco(PResp,[quiero,vale4,no])),
    obtener_accion(PResp,Resp),
    (Resp=no->EF=truco(PResp),R=fin(P)
    ;Resp=quiero->EF=retruco(P),R=continuar
    ;Resp=vale4->enviar_evento(todos,canto_vale4(PResp)),
                 responder_apuesta(vale4(PResp),P,PResp,EF,R)
    ).

responder_apuesta(vale4(P),PResp,P,EF,R):-
    enviar_evento(todos,responder_vale4(PResp,[quiero,no])),
    obtener_accion(PResp,Resp),
    (Resp=no->EF=retruco(PResp),R=fin(P)
    ;Resp=quiero->EF=vale4(P),R=continuar
    ;EF=retruco(PResp),R=fin(P)
    ).

% ====================================================================
% 11. AUXILIARES
% ====================================================================
calcular_puntos(nada,1). calcular_puntos(truco(_),2).
calcular_puntos(retruco(_),3). calcular_puntos(vale4(_),4).

sumar_puntos(G,J1,_,Ptos,P1,P2,NP1,P2):-G==J1,NP1 is P1+Ptos.
sumar_puntos(G,_,J2,Ptos,P1,P2,P1,NP2):-G==J2,NP2 is P2+Ptos.
sumar_puntos(empate,_,_,_,P1,P2,P1,P2).

cambiar_mano(M,J1,J2,M1):-(M==J1->M1=J2;M1=J1).

determinar_saliente(PT,PR,R,PT2,PR2,CT2,CR2,CT1,CR1):-
    (R==parda->PT2=PT,PR2=PR,CT2=CT1,CR2=CR1
    ;R==PT->PT2=PT,PR2=PR,CT2=CT1,CR2=CR1
    ;PT2=PR,PR2=PT,CT2=CR1,CR2=CT1
    ).

evaluar_tirada(C1,C2,P1,P2,G):-
    valor(C1,V1),valor(C2,V2),
    (V1>V2->G=P1;V2>V1->G=P2;G=parda).

evaluar_ganador_final([G1,G2,G3],Mano,G):-
    (G1==G2,G1\=parda->G=G1
    ;G1=parda,G2\=parda->G=G2
    ;G1=parda,G2=parda->G=Mano
    ;G1\=parda,G2=parda->G=G1
    ;G3=parda->G=G1
    ;G=G3
    ).

% ====================================================================
% 12. PEDIR CARTA
% ====================================================================
pedir_carta(J,Cartas,Carta,Restantes,Abandono):-
    enviar_evento(todos,turno_carta(J)),
    enviar_cartas(J,Cartas),
    obtener_accion(J,Raw),
    normalize_input(Raw,Input),
    (Input=no->Abandono=true,Carta=nula,Restantes=Cartas
    ;number(Input)->nth1(Input,Cartas,Carta),select(Carta,Cartas,Restantes),
                    enviar_evento(todos,carta_jugada(J,Carta)),Abandono=false
    ;atom_number(Input,I)->nth1(I,Cartas,Carta),select(Carta,Cartas,Restantes),
                           enviar_evento(todos,carta_jugada(J,Carta)),Abandono=false
    ;Abandono=true,Carta=nula,Restantes=Cartas
    ).

normalize_input(X,N):-
    (number(X)->N=X
    ;atom(X)->(atom_number(X,N)->true;N=X)
    ;string(X)->(number_string(N,X)->true;N=X)
    ;N=X
    ).
