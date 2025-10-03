# LightSaber-AI-Client
Delphi AI client with advanced capabilities


For the moment it only supports Gemini, but it can be easily supported to support multiple LLMs by extending TLLMObject.

 * Support for sending multiple files to AI
 * Support for multi-turn chat
 * GUI to set up the LLM parameters
 * Save settings to disk for later use
 * Save JSON files to disk for debugging or later reuse.
 * Calculates total used tokens
 * Safety parameters (reject inappropriate input) 
 * Roles
 * Heavily tested 
 * Delphi 13
 * VCL 
 * FMX
 * Delivered as Delphi package (DPK)
 
 
TAiClient -> TAiClientEx 
                  |
                  + TLLMObject -> TLLMGemini
                  
About 1500 lines of code