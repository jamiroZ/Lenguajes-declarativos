ganador(piedra, tijera).
ganador(tijera, papel).
ganador(papel, piedra).

jugar(J1, J2, gana_j1) :-
    ganador(J1, J2).

jugar(J1, J2, gana_j2) :-
    ganador(J2, J1).

jugar(X, X, empate).