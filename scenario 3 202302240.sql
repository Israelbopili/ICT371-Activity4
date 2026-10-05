-- =========================================================
-- ICT371 Activity 4 - Scenario 3: Hostel Room Allocation
-- =========================================================

DROP TABLE IF EXISTS allocations CASCADE;
DROP TABLE IF EXISTS hostel_rooms CASCADE;

CREATE TABLE hostel_rooms (
    room_id          SERIAL PRIMARY KEY,
    room_number      VARCHAR(10) NOT NULL,
    available_spaces INTEGER NOT NULL CHECK (available_spaces >= 0)
);

CREATE TABLE allocations (
    allocation_id  SERIAL PRIMARY KEY,
    student_number VARCHAR(20) NOT NULL,
    room_id        INTEGER REFERENCES hostel_rooms(room_id),
    status         VARCHAR(20) DEFAULT 'ACTIVE'
);

INSERT INTO hostel_rooms (room_number, available_spaces) VALUES
('A101', 5),
('B202', 1),
('C303', 0);

-- 2. IF ELSIF ELSE
DO $$
DECLARE v_spaces INTEGER;
BEGIN
    SELECT available_spaces INTO v_spaces FROM hostel_rooms WHERE room_id = 1;
    IF v_spaces = 0 THEN
        RAISE NOTICE 'Room 1 is FULL.';
    ELSIF v_spaces = 1 THEN
        RAISE NOTICE 'Room 1 has ONE space left.';
    ELSE
        RAISE NOTICE 'Room 1 has SEVERAL spaces (% left).', v_spaces;
    END IF;
END $$;

-- 3a. WHILE
DO $$
DECLARE i INTEGER := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Hostel inspection day #%', i;
        i := i + 1;
    END LOOP;
END $$;

-- 3b. Numeric FOR
DO $$
BEGIN
    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Room check #%', n;
    END LOOP;
END $$;

-- 4. allocate_room
CREATE OR REPLACE PROCEDURE allocate_room(
    p_student_number VARCHAR,
    p_room_id        INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE v_spaces INTEGER;
BEGIN
    IF p_student_number IS NULL OR TRIM(p_student_number) = '' THEN
        RAISE EXCEPTION 'Student number cannot be blank.';
    END IF;

    SELECT available_spaces INTO v_spaces
    FROM hostel_rooms WHERE room_id = p_room_id FOR UPDATE;

    IF v_spaces IS NULL THEN
        RAISE EXCEPTION 'Room % does not exist.', p_room_id;
    END IF;

    IF v_spaces < 1 THEN
        RAISE EXCEPTION 'Room % is full.', p_room_id;
    END IF;

    UPDATE hostel_rooms
       SET available_spaces = available_spaces - 1
     WHERE room_id = p_room_id;

    INSERT INTO allocations (student_number, room_id, status)
    VALUES (p_student_number, p_room_id, 'ACTIVE');

    RAISE NOTICE 'Allocated room % to student %.', p_room_id, p_student_number;
END $$;

-- 5. Calls
CALL allocate_room('STU100', 1);
CALL allocate_room('STU101', 2);
DO $$
BEGIN
    CALL allocate_room('STU102', 3);  -- full room
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Expected failure: %', SQLERRM;
END $$;

SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;

-- 6. check_out (idempotent)
CREATE OR REPLACE PROCEDURE check_out(p_allocation_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE v_status VARCHAR(20); v_room INTEGER;
BEGIN
    SELECT status, room_id INTO v_status, v_room
    FROM allocations WHERE allocation_id = p_allocation_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Allocation % not found.', p_allocation_id;
    END IF;

    IF v_status = 'COMPLETE' THEN
        RAISE NOTICE 'Allocation % already completed – no space freed.', p_allocation_id;
        RETURN;
    END IF;

    UPDATE hostel_rooms
       SET available_spaces = available_spaces + 1
     WHERE room_id = v_room;

    UPDATE allocations SET status = 'COMPLETE'
     WHERE allocation_id = p_allocation_id;

    RAISE NOTICE 'Allocation % checked out; space in room % freed.',
        p_allocation_id, v_room;
END $$;

CALL check_out(1);
CALL check_out(1);   -- must not free again

-- 7. Explicit cursor – full / nearly full rooms
DO $$
DECLARE
    cur_rooms CURSOR FOR
        SELECT room_id, room_number, available_spaces
        FROM hostel_rooms
        WHERE available_spaces <= 1
        ORDER BY room_id;
    r RECORD;
BEGIN
    OPEN cur_rooms;
    LOOP
        FETCH cur_rooms INTO r;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Room % (%) has % space(s) left.',
            r.room_id, r.room_number, r.available_spaces;
    END LOOP;
    CLOSE cur_rooms;
END $$;

-- 8. Blank student number – EXCEPTION
DO $$
BEGIN
    CALL allocate_room('', 1);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Handled invalid input: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM hostel_rooms ORDER BY room_id;
SELECT * FROM allocations ORDER BY allocation_id;