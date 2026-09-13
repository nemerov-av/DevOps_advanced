# Этап 1: Builder
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Копируем зависимости отдельно для кэширования слоя
COPY go.mod go.sum ./
RUN go mod download

# Копируем остальной исходный код
COPY . .

# Собираем бинарный файл
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server ./cmd/server/app.go

# Этап 2: Runner
FROM alpine:latest
WORKDIR /root/

# Копируем только скомпилированный бинарный файл из этапа builder
COPY --from=builder /app/server .

# Запуск приложения
CMD ["./server"]