C     ROOTS OF A QUADRATIC, WITH AN ARITHMETIC IF
      PROGRAM ROOTS
      REAL A, B, C, D, X1, X2
      COMMON /COEF/ A, B, C
      READ (5, *) A, B, C
      IF (A .EQ. 0.0) GO TO 90
      D = B**2 - 4.0 * A * C
      IF (D) 30, 20, 10
   10 X1 = (-B + SQRT(D)) / (2.0 * A)
      X2 = (-B - SQRT(D)) / (2.0 * A)
      WRITE (6, 200) X1, X2
      GO TO 99
   20 X1 = -B / (2.0 * A)
      WRITE (6, 210) X1
      GO TO 99
   30 WRITE (6, 220)
      GO TO 99
   90 WRITE (6, 230)
   99 STOP
  200 FORMAT (' TWO ROOTS: ', 2F12.5)
  210 FORMAT (' ONE ROOT:  ', F12.5)
  220 FORMAT (' NO REAL ROOTS')
  230 FORMAT (' NOT A QUADRATIC')
      END
