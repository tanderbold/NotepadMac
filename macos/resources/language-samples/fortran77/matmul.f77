C     MULTIPLY TWO MATRICES
      SUBROUTINE MATMLT(A, B, C, N)
      INTEGER N, I, J, K
      DOUBLE PRECISION A(N,N), B(N,N), C(N,N)
      DO 30 I = 1, N
         DO 20 J = 1, N
            C(I,J) = 0.0D0
            DO 10 K = 1, N
               C(I,J) = C(I,J) + A(I,K) * B(K,J)
   10       CONTINUE
   20    CONTINUE
   30 CONTINUE
      RETURN
      END
C
      PROGRAM DRIVER
      PARAMETER (N = 3)
      DOUBLE PRECISION A(N,N), B(N,N), C(N,N)
      DATA A /1.0D0, 0.0D0, 0.0D0, 0.0D0, 1.0D0, 0.0D0,
     +        0.0D0, 0.0D0, 1.0D0/
      DATA B /9*2.0D0/
      CALL MATMLT(A, B, C, N)
      WRITE (6, 900) ((C(I,J), J = 1, N), I = 1, N)
  900 FORMAT (3F8.2)
      END
