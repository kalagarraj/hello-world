terraform {
  required_version = ">= 1.6"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = ">= 3.0"
    }
  }
}

locals {
  prometheus_config = templatefile("${path.module}/templates/prometheus.yml.tftpl", {
    stack = var.stack_name
    apps  = var.scrape_targets
  })

  loki_config = templatefile("${path.module}/templates/loki-config.yaml.tftpl", {
    retention_hours = var.retention_hours
  })

  tempo_config = templatefile("${path.module}/templates/tempo.yaml.tftpl", {
    retention_hours = var.retention_hours
  })

  collector_config = templatefile("${path.module}/templates/otel-collector.yaml.tftpl", {
    stack = var.stack_name
  })

  grafana_datasources = templatefile("${path.module}/templates/grafana-datasources.yaml.tftpl", {})

  grafana_dashboard_provider = templatefile("${path.module}/templates/grafana-dashboards.yaml.tftpl", {
    folder = var.grafana_dashboard_folder
  })

  dashboard_files = var.dashboards_dir == null ? {} : {
    for f in fileset(var.dashboards_dir, "*.json") :
    f => file("${var.dashboards_dir}/${f}")
  }
}

# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

resource "docker_image" "prometheus" {
  name         = var.images.prometheus
  keep_locally = true
}

resource "docker_image" "loki" {
  name         = var.images.loki
  keep_locally = true
}

resource "docker_image" "tempo" {
  name         = var.images.tempo
  keep_locally = true
}

resource "docker_image" "collector" {
  name         = var.images.otel_collector
  keep_locally = true
}

resource "docker_image" "grafana" {
  name         = var.images.grafana
  keep_locally = true
}

# ---------------------------------------------------------------------------
# Persistent volumes
# ---------------------------------------------------------------------------

resource "docker_volume" "prometheus" {
  name = "${var.name_prefix}prometheus-data"
}

resource "docker_volume" "loki" {
  name = "${var.name_prefix}loki-data"
}

resource "docker_volume" "tempo" {
  name = "${var.name_prefix}tempo-data"
}

resource "docker_volume" "grafana" {
  name = "${var.name_prefix}grafana-data"
}

# ---------------------------------------------------------------------------
# Metrics store
# ---------------------------------------------------------------------------

resource "docker_container" "prometheus" {
  name     = "${var.name_prefix}prometheus"
  image    = docker_image.prometheus.image_id
  restart  = "unless-stopped"
  must_run = true
  user     = "root"

  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=${var.retention_hours}h",
    "--web.enable-lifecycle",
    # Tempo's metrics generator remote-writes RED metrics into Prometheus.
    "--web.enable-remote-write-receiver",
    "--enable-feature=exemplar-storage",
  ]

  upload {
    file    = "/etc/prometheus/prometheus.yml"
    content = local.prometheus_config
  }

  volumes {
    volume_name    = docker_volume.prometheus.name
    container_path = "/prometheus"
  }

  networks_advanced {
    name    = var.network_name
    aliases = ["prometheus"]
  }

  ports {
    internal = 9090
    external = var.ports.prometheus
  }

  labels {
    label = "com.hello-world.role"
    value = "observability"
  }
}

# ---------------------------------------------------------------------------
# Log store
# ---------------------------------------------------------------------------

resource "docker_container" "loki" {
  name     = "${var.name_prefix}loki"
  image    = docker_image.loki.image_id
  restart  = "unless-stopped"
  must_run = true
  user     = "root"

  command = ["-config.file=/etc/loki/local-config.yaml"]

  upload {
    file    = "/etc/loki/local-config.yaml"
    content = local.loki_config
  }

  volumes {
    volume_name    = docker_volume.loki.name
    container_path = "/loki"
  }

  networks_advanced {
    name    = var.network_name
    aliases = ["loki"]
  }

  ports {
    internal = 3100
    external = var.ports.loki
  }

  labels {
    label = "com.hello-world.role"
    value = "observability"
  }
}

# ---------------------------------------------------------------------------
# Trace store
# ---------------------------------------------------------------------------

resource "docker_container" "tempo" {
  name     = "${var.name_prefix}tempo"
  image    = docker_image.tempo.image_id
  restart  = "unless-stopped"
  must_run = true
  user     = "root"

  command = ["-config.file=/etc/tempo/tempo.yaml"]

  upload {
    file    = "/etc/tempo/tempo.yaml"
    content = local.tempo_config
  }

  volumes {
    volume_name    = docker_volume.tempo.name
    container_path = "/var/tempo"
  }

  networks_advanced {
    name    = var.network_name
    aliases = ["tempo"]
  }

  ports {
    internal = 3200
    external = var.ports.tempo
  }

  depends_on = [docker_container.prometheus]

  labels {
    label = "com.hello-world.role"
    value = "observability"
  }
}

# ---------------------------------------------------------------------------
# Single ingestion point for app telemetry
# ---------------------------------------------------------------------------

resource "docker_container" "collector" {
  name     = "${var.name_prefix}otel-collector"
  image    = docker_image.collector.image_id
  restart  = "unless-stopped"
  must_run = true

  command = ["--config=/etc/otelcol/config.yaml"]

  upload {
    file    = "/etc/otelcol/config.yaml"
    content = local.collector_config
  }

  networks_advanced {
    name    = var.network_name
    aliases = ["otel-collector"]
  }

  ports {
    internal = 4317
    external = var.ports.otlp_grpc
  }

  ports {
    internal = 4318
    external = var.ports.otlp_http
  }

  depends_on = [
    docker_container.tempo,
    docker_container.loki,
  ]

  labels {
    label = "com.hello-world.role"
    value = "observability"
  }
}

# ---------------------------------------------------------------------------
# Grafana
# ---------------------------------------------------------------------------

resource "docker_container" "grafana" {
  name     = "${var.name_prefix}grafana"
  image    = docker_image.grafana.image_id
  restart  = "unless-stopped"
  must_run = true

  env = [
    "GF_SECURITY_ADMIN_USER=${var.grafana_admin_user}",
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
    "GF_AUTH_ANONYMOUS_ENABLED=${var.grafana_anonymous_access}",
    "GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer",
    "GF_USERS_DEFAULT_THEME=dark",
    "GF_ANALYTICS_REPORTING_ENABLED=false",
    "GF_ANALYTICS_CHECK_FOR_UPDATES=false",
    "GF_FEATURE_TOGGLES_ENABLE=traceqlEditor",
    "GF_INSTALL_PLUGINS=${join(",", var.grafana_plugins)}",
  ]

  upload {
    file    = "/etc/grafana/provisioning/datasources/datasources.yaml"
    content = local.grafana_datasources
  }

  upload {
    file    = "/etc/grafana/provisioning/dashboards/dashboards.yaml"
    content = local.grafana_dashboard_provider
  }

  # Dashboards live in infra/shared/dashboards so the same JSON can be imported
  # into Azure Managed Grafana.
  dynamic "upload" {
    for_each = local.dashboard_files
    content {
      file    = "/etc/grafana/provisioning/dashboards/files/${upload.key}"
      content = upload.value
    }
  }

  volumes {
    volume_name    = docker_volume.grafana.name
    container_path = "/var/lib/grafana"
  }

  networks_advanced {
    name    = var.network_name
    aliases = ["grafana"]
  }

  ports {
    internal = 3000
    external = var.ports.grafana
  }

  depends_on = [
    docker_container.prometheus,
    docker_container.loki,
    docker_container.tempo,
  ]

  labels {
    label = "com.hello-world.role"
    value = "observability"
  }
}
