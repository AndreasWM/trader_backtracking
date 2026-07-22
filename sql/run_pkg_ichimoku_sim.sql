BEGIN
    pkg_ichimoku_sim.run_simulation(
        p_start_date    => DATE '2025-07-02',
        p_end_date      => DATE '2026-06-30',
        p_capital       => 100000,
        p_max_positions => 10
    );
END;
/