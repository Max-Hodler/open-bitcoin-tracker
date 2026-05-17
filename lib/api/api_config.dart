class ApiConfig {
  const ApiConfig({
    this.requestTimeout = const Duration(seconds: 10),
  });

  final Duration requestTimeout;
}
