-- =========================================================
-- ICT371 Activity 4 - Scenario 2: Computer Lab Reservations
-- =========================================================

DROP TABLE IF EXISTS reservations CASCADE;
DROP TABLE IF EXISTS lab_sessions CASCADE;

CREATE TABLE lab_sessions (
    session_id           SERIAL PRIMARY KEY,
    session_name         VARCHAR(100) NOT NULL,
    available_workstations INTEGER NOT NULL CHECK (available_workstations >= 0)
);

CREATE TABLE reservations (
    reservation_id  SERIAL PRIMARY KEY,
    session_id      INTEGER REFERENCES lab_sessions(session_id),
    lecturer        VARCHAR(50) NOT NULL,
    workstations    INTEGER NOT NULL CHECK (workstations > 0),
    status          VARCHAR(20) DEFAULT 'ACTIVE'
);

INSERT INTO lab_sessions (session_name, available_workstations) VALUES
('Monday 08:00 - Databases',   20),
('Tuesday 10:00 - Networks',    4),
('Wednesday 14:00 - AI',        0);

-- 2. IF ELSIF ELSE
DO $$
DECLARE v_avail INTEGER;
BEGIN
    SELECT available_workstations INTO v_avail FROM lab_sessions WHERE session_id = 1;
    IF v_avail = 0 THEN
        RAISE NOTICE 'Session 1 is FULL.';
    ELSIF v_avail <= 5 THEN
        RAISE NOTICE 'Session 1 is NEARLY FULL (% left).', v_avail;
    ELSE
        RAISE NOTICE 'Session 1 has ENOUGH workstations (% left).', v_avail;
    END IF;
END $$;

-- 3a. WHILE
DO $$
DECLARE i INTEGER := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder #%', i;
        i := i + 1;
    END LOOP;
END $$;

-- 3b. Numeric FOR
DO $$
BEGIN
    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Workstation check #%', n;
    END LOOP;
END $$;

-- 4. reserve_workstations
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id INTEGER,
    p_lecturer   VARCHAR,
    p_qty        INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE v_avail INTEGER;
BEGIN
    IF p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION 'Invalid workstation quantity: %', p_qty;
    END IF;

    SELECT available_workstations INTO v_avail
    FROM lab_sessions WHERE session_id = p_session_id FOR UPDATE;

    IF v_avail IS NULL THEN
        RAISE EXCEPTION 'Session % does not exist.', p_session_id;
    END IF;

    IF v_avail < p_qty THEN
        RAISE EXCEPTION 'Not enough workstations in session % (avail=%, req=%).',
            p_session_id, v_avail, p_qty;
    END IF;

    UPDATE lab_sessions
       SET available_workstations = available_workstations - p_qty
     WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, workstations, status)
    VALUES (p_session_id, p_lecturer, p_qty, 'ACTIVE');

    RAISE NOTICE 'Reserved % workstation(s) in session % for %.',
        p_qty, p_session_id, p_lecturer;
END $$;

-- 5. Calls
CALL reserve_workstations(1, 'Dr Mwansa', 5);
CALL reserve_workstations(2, 'Dr Banda',  2);
DO $$
BEGIN
    CALL reserve_workstations(2, 'Dr Phiri', 10);  -- exceeds
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Expected failure: %', SQLERRM;
END $$;

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;

-- 6. cancel_reservation (idempotent)
CREATE OR REPLACE PROCEDURE cancel_reservation(p_res_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE v_status VARCHAR(20); v_session INTEGER; v_qty INTEGER;
BEGIN
    SELECT status, session_id, workstations
      INTO v_status, v_session, v_qty
      FROM reservations WHERE reservation_id = p_res_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Reservation % not found.', p_res_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % already cancelled – no release.', p_res_id;
        RETURN;
    END IF;

    UPDATE lab_sessions
       SET available_workstations = available_workstations + v_qty
     WHERE session_id = v_session;

    UPDATE reservations SET status = 'CANCELLED'
     WHERE reservation_id = p_res_id;

    RAISE NOTICE 'Reservation % cancelled; % workstation(s) released.',
        p_res_id, v_qty;
END $$;

CALL cancel_reservation(1);
CALL cancel_reservation(1);  -- second call should not release again

-- 7. Explicit cursor – sessions with few workstations
DO $$
DECLARE
    cur_sessions CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions
        WHERE available_workstations <= 5
        ORDER BY session_id;
    r RECORD;
BEGIN
    OPEN cur_sessions;
    LOOP
        FETCH cur_sessions INTO r;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Session % (%) has only % workstation(s).',
            r.session_id, r.session_name, r.available_workstations;
    END LOOP;
    CLOSE cur_sessions;
END $$;

-- 8. Zero workstations – EXCEPTION
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr Test', 0);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Handled invalid quantity: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;