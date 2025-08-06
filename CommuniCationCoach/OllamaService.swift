import Foundation

class OllamaService {
    
    // Check if the required Ollama model is available.
    func checkModelAvailability(modelName: String = "gemma3n:e4b", completion: @escaping (Bool) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ollama")
        process.arguments = ["list"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        process.terminationHandler = { process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                completion(output.contains(modelName))
            } else {
                completion(false)
            }
        }
        
        do {
            try process.run()
        } catch {
            print("Error checking Ollama model availability: \(error)")
            completion(false)
        }
    }
    
    // We will implement the prompt execution logic next.
    func executePrompt(prompt: String, completion: @escaping (String) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ollama")
        process.arguments = ["run", "gemma3:1b", prompt]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        process.terminationHandler = { process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                completion(output.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                completion("Error: Could not decode Ollama response.")
            }
        }
        
        do {
            try process.run()
        } catch {
            print("Error executing Ollama prompt: \(error)")
            completion("Error: Could not run Ollama process.")
        }
    }
} 
