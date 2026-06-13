-- name: CreateUser :one
INSERT INTO users (name, email, age)
VALUES ($1, $2, $3)
RETURNING *;

-- name: GetUser :one
SELECT * FROM users
WHERE id = $1;

-- name: ListUsers :many
SELECT * FROM users
ORDER BY id DESC
LIMIT $1 OFFSET $2;

-- name: UpdateUser :one
UPDATE users
SET name = $2, email = $3, age = $4, updated_at = now()
WHERE id = $1
RETURNING *;

-- name: DeleteUser :exec
DELETE FROM users
WHERE id = $1;

-- name: CountUsers :one
SELECT count(*) FROM users;
