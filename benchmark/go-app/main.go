package main

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"runtime"
	"strconv"
	"time"

	"benchapp/db/sqlc"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
)

//go:embed db/migrations/*.sql
var migrationsFS embed.FS

type server struct {
	q *sqlc.Queries
}

type userInput struct {
	Name  string `json:"name"`
	Email string `json:"email"`
	Age   int32  `json:"age"`
}

func main() {
	dsn := getenv("DATABASE_URL", "postgres://bench:bench@localhost:5432/bench?sslmode=disable")

	if err := runMigrations(dsn); err != nil {
		log.Fatalf("migrations: %v", err)
	}

	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		log.Fatalf("parse config: %v", err)
	}
	cfg.MaxConns = int32(envInt("DB_MAX_CONNS", 30))
	cfg.MinConns = int32(envInt("DB_MIN_CONNS", 10))

	ctx := context.Background()
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		log.Fatalf("pool: %v", err)
	}
	defer pool.Close()
	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("ping: %v", err)
	}

	s := &server{q: sqlc.New(pool)}

	r := chi.NewRouter()
	r.Get("/health", s.health)
	r.Route("/users", func(r chi.Router) {
		r.Post("/", s.createUser)
		r.Get("/", s.listUsers)
		r.Get("/{id}", s.getUser)
		r.Put("/{id}", s.updateUser)
		r.Delete("/{id}", s.deleteUser)
	})

	addr := ":" + getenv("PORT", "8080")
	log.Printf("go-app listening on %s (GOMAXPROCS=%d)", addr, runtime.GOMAXPROCS(0))
	srv := &http.Server{
		Addr:         addr,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
	}
	log.Fatal(srv.ListenAndServe())
}

func runMigrations(dsn string) error {
	db, err := goose.OpenDBWithDriver("pgx", dsn)
	if err != nil {
		return err
	}
	defer db.Close()
	goose.SetBaseFS(migrationsFS)
	if err := goose.SetDialect("postgres"); err != nil {
		return err
	}
	return goose.Up(db, "db/migrations")
}

// ensure pgx stdlib driver is registered for goose
var _ = stdlib.GetDefaultDriver

func (s *server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *server) createUser(w http.ResponseWriter, r *http.Request) {
	var in userInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	u, err := s.q.CreateUser(r.Context(), sqlc.CreateUserParams{
		Name:  in.Name,
		Email: in.Email,
		Age:   in.Age,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, u)
}

func (s *server) getUser(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}
	u, err := s.q.GetUser(r.Context(), id)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "not found")
			return
		}
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *server) listUsers(w http.ResponseWriter, r *http.Request) {
	limit := int32(queryInt(r, "limit", 20))
	offset := int32(queryInt(r, "offset", 0))
	users, err := s.q.ListUsers(r.Context(), sqlc.ListUsersParams{Limit: limit, Offset: offset})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, users)
}

func (s *server) updateUser(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}
	var in userInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeError(w, http.StatusBadRequest, "invalid body")
		return
	}
	u, err := s.q.UpdateUser(r.Context(), sqlc.UpdateUserParams{
		ID:    id,
		Name:  in.Name,
		Email: in.Email,
		Age:   in.Age,
	})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "not found")
			return
		}
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, u)
}

func (s *server) deleteUser(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}
	if err := s.q.DeleteUser(r.Context(), id); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func queryInt(r *http.Request, key string, def int) int {
	if v := r.URL.Query().Get(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}
