C     TRAPEZOIDAL RULE FOR THE INTEGRAL OF F OVER (A,B)
      PROGRAM TRAPZ
      IMPLICIT NONE
      INTEGER N, I
      REAL A, B, H, S, F
      EXTERNAL F
      A = 0.0
      B = 1.0
      N = 100
      H = (B - A) / N
      S = 0.5 * (F(A) + F(B))
      DO 10 I = 1, N - 1
         S = S + F(A + I * H)
   10 CONTINUE
      S = S * H
      WRITE (*, 100) S
  100 FORMAT (' INTEGRAL = ', F10.6)
      STOP
      END
C
      REAL FUNCTION F(X)
      REAL X
      F = X * X
      RETURN
      END
