import 'api_exception.dart';

/// Minimal success/failure wrapper so controllers avoid try/catch at every
/// call site.
sealed class Result<T> {
  const Result();

  R when<R>({
    required R Function(T value) ok,
    required R Function(ApiException err) err,
  }) {
    final self = this;
    return switch (self) {
      Ok<T>(:final value) => ok(value),
      Err<T>(:final error) => err(error),
    };
  }

  T? get valueOrNull => this is Ok<T> ? (this as Ok<T>).value : null;
  bool get isOk => this is Ok<T>;
}

class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

class Err<T> extends Result<T> {
  const Err(this.error);
  final ApiException error;
}
