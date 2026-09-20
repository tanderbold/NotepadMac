C     BUBBLE SORT OF AN INTEGER ARRAY
      SUBROUTINE BSORT(IA, N)
      INTEGER N, IA(N), I, J, ITMP
      LOGICAL SWAPPD
      DO 20 I = N - 1, 1, -1
         SWAPPD = .FALSE.
         DO 10 J = 1, I
            IF (IA(J) .GT. IA(J+1)) THEN
               ITMP = IA(J)
               IA(J) = IA(J+1)
               IA(J+1) = ITMP
               SWAPPD = .TRUE.
            END IF
   10    CONTINUE
         IF (.NOT. SWAPPD) RETURN
   20 CONTINUE
      RETURN
      END
C
      PROGRAM TSORT
      INTEGER IA(8), I
      DATA IA /5, 3, 8, 1, 9, 2, 7, 4/
      CALL BSORT(IA, 8)
      PRINT *, (IA(I), I = 1, 8)
      END
