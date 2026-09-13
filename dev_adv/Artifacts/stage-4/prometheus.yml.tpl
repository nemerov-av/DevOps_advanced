global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Мониторинг самого Prometheus
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Автообнаружение Node Exporter через Consul
  - job_name: 'node-exporter'
    consul_sd_configs:
      - server: '127.0.0.1:8500' # Локальный агент Consul на ноде мониторинга
        services: ['node-exporter']
    relabel_configs:
      - source_labels: [__meta_consul_node]
        target_label: instance