import App
import Vapor

@main
struct Entrypoint {
  static func main() async {
    let loops = MultiThreadedEventLoopGroup(numberOfThreads: 2)
    var app: Application?
    do {
      let environment = try Environment.detect()
      let created = try await Application.make(environment, .shared(loops))
      app = created
      let arguments = CommandLine.arguments
      let schemaMode = arguments.contains("migrate") || arguments.contains("seed")
      let wrongHostname = arguments.contains("tls-check") && arguments.contains("--wrong-hostname")
      try configure(
        created, schemaMode: schemaMode, wrongHostname: wrongHostname,
        tlsProbe: arguments.contains("tls-check"))
      try await created.execute()
      try await created.asyncShutdown()
      try await loops.shutdownGracefully()
    } catch {
      // No invitation secrets, tokens, SQL bind values or database credentials in errors.
      FileHandle.standardError.write(
        Data(
          "Invitation command failed; check input, configuration, TLS, roles and database\n".utf8))
      if let app { try? await app.asyncShutdown() }
      try? await loops.shutdownGracefully()
      exit(1)
    }
  }
}
