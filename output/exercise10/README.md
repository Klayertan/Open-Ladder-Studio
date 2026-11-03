# Exercise 10 - traffic light

Use `Exercise-10-Traffic-Light.ladder` with Open Ladder Studio 0.2. Show Simulation, choose Run, then press X0. The cycle is green for 10 seconds, yellow for 2 seconds, red for 5 seconds, then repeats. X1 switches all lamps off and clears the timers; X0 restarts at green. Every input/output has a Japanese comment.

`KADAI10.MBS` is an experimental real-format Renri export; read `RENRI-COMPATIBILITY.md` before submitting it. The current environment cannot verify opening it in Renri. Native app simulation and Renri application compatibility are separate checks.

The runtime screenshot PDF is at `../pdf/Exercise-10-Running-Screen.pdf`. Its original full-screen PNG is `01-running-screen.png`. It preserves the actual system clock and displays the running yellow phase (t = 214.72 seconds, or 10.72 seconds into a 17-second cycle).

The stop-state assumption is all lamps off, with restart at green. The worksheet specifies the colour timings but no exact X/Y addresses and no stop-state behaviour.
