-- =========================================================
-- ICT371 Activity 4 - Scenario 1: Library Book Loans
-- =========================================================

-- 1. Create tables
DROP TABLE IF EXISTS book_loans CASCADE;
DROP TABLE IF EXISTS books CASCADE;

CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INTEGER NOT NULL CHECK (available_copies >= 0)
);

CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INTEGER REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INTEGER NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(20) DEFAULT 'ACTIVE'
);

-- Add at least three books
INSERT INTO books (title, available_copies) VALUES
('Database Systems',        3),
('Programming in Python',   1),
('Operating Systems',       0);

-- 2. IF ELSIF ELSE – stock status of one book
DO $$
DECLARE
    v_copies INTEGER;
BEGIN
    SELECT available_copies INTO v_copies FROM books WHERE book_id = 1;
    IF v_copies = 0 THEN
        RAISE NOTICE 'Book 1: UNAVAILABLE (no copies).';
    ELSIF v_copies <= 2 THEN
        RAISE NOTICE 'Book 1: LOW ON COPIES (only %).', v_copies;
    ELSE
        RAISE NOTICE 'Book 1: SUFFICIENTLY STOCKED (% copies).', v_copies;
    END IF;
END $$;

-- 3a. WHILE – three overdue reminder numbers
DO $$
DECLARE
    i INTEGER := 1;
BEGIN
    WHILE i <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number: %', i;
        i := i + 1;
    END LOOP;
END $$;

-- 3b. Numeric FOR – three library shelf numbers
DO $$
BEGIN
    FOR s IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number: %', s;
    END LOOP;
END $$;

-- 4. borrow_book procedure
CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id        INTEGER,
    p_student_number VARCHAR,
    p_quantity       INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INTEGER;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: % (must be > 0).', p_quantity;
    END IF;

    SELECT available_copies INTO v_available
    FROM books WHERE book_id = p_book_id FOR UPDATE;

    IF v_available IS NULL THEN
        RAISE EXCEPTION 'Book % does not exist.', p_book_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE EXCEPTION 'Not enough copies for book % (available=%, requested=%).',
            p_book_id, v_available, p_quantity;
    END IF;

    UPDATE books
       SET available_copies = available_copies - p_quantity
     WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student_number, p_quantity, 'ACTIVE');

    RAISE NOTICE 'Loan recorded: book %, student %, qty %.',
        p_book_id, p_student_number, p_quantity;
END $$;

-- 5. Call borrow_book: two valid + one that exceeds
CALL borrow_book(1, 'STU001', 1);
CALL borrow_book(2, 'STU002', 1);
-- This one should fail (only 1 copy left of book 2, but request 5)
DO $$
BEGIN
    CALL borrow_book(2, 'STU003', 5);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Expected failure: %', SQLERRM;
END $$;

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;

-- 6. return_book procedure (idempotent)
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INTEGER)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
    v_book   INTEGER;
    v_qty    INTEGER;
BEGIN
    SELECT loan_status, book_id, quantity
      INTO v_status, v_book, v_qty
      FROM book_loans WHERE loan_id = p_loan_id FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Loan % does not exist.', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % already returned – no stock restored.', p_loan_id;
        RETURN;
    END IF;

    UPDATE books
       SET available_copies = available_copies + v_qty
     WHERE book_id = v_book;

    UPDATE book_loans
       SET loan_status = 'RETURNED'
     WHERE loan_id = p_loan_id;

    RAISE NOTICE 'Loan % returned; % copies restored.', p_loan_id, v_qty;
END $$;

CALL return_book(1);
CALL return_book(1);   -- second call must NOT restore again

-- 7. Explicit cursor – books with few copies
DO $$
DECLARE
    cur_books CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books
        WHERE available_copies <= 2
        ORDER BY book_id;
    r RECORD;
BEGIN
    OPEN cur_books;
    LOOP
        FETCH cur_books INTO r;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low stock -> id=%, title=%, copies=%',
            r.book_id, r.title, r.available_copies;
    END LOOP;
    CLOSE cur_books;
END $$;

-- 8. Borrow zero copies – handle with EXCEPTION
DO $$
BEGIN
    CALL borrow_book(1, 'STU004', 0);
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Handled invalid quantity: %', SQLERRM;
END $$;

-- 9. Final state
SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;