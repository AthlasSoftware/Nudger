//
//  ContentSearcher.swift
//  Nudger
//
//  Created on 2025-10-28.
//

import Foundation
import os.log

/// Searches for real content URLs using Brave Search API
class ContentSearcher {
    
    private let apiKey: String?
    private let baseURL = "https://api.search.brave.com/res/v1"
    
    init() {
        // Use Brave API key from Config
        self.apiKey = Config.braveAPIKey.isEmpty ? nil : Config.braveAPIKey
    }
    
    /// Search for relevant content based on context and query
    /// Returns a real URL that actually exists
    func search(query: String, context: String) async -> URL? {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            Log.llm.warning("No Brave API key configured")
            return nil
        }
        
        // Build search query based on context
        let searchQuery = buildSearchQuery(query: query, context: context)
        
        guard let url = URL(string: "\(baseURL)/web/search") else {
            return nil
        }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: searchQuery),
            URLQueryItem(name: "count", value: "3")
        ]
        
        guard let requestURL = components?.url else {
            return nil
        }
        
        var request = URLRequest(url: requestURL)
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Log.llm.warning("Brave Search API: invalid response")
                return nil
            }
            
            Log.llm.debug("Brave Search API status: \(httpResponse.statusCode)")
            
            guard httpResponse.statusCode == 200 else {
                if let errorText = String(data: data, encoding: .utf8) {
                    Log.llm.warning("Brave Search API error (\(httpResponse.statusCode)): \(errorText)")
                }
                return nil
            }
            
            // Parse response
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let web = json?["web"] as? [String: Any]
            let results = web?["results"] as? [[String: Any]]
            
            Log.llm.debug("Brave Search returned \(results?.count ?? 0) results")
            
            // Determine current platform from context
            let currentPlatform = detectPlatform(from: context)
            
            // Filter results to match current platform if possible
            if let platformResult = results?.first(where: { result in
                guard let urlString = result["url"] as? String,
                      let url = URL(string: urlString) else {
                    return false
                }
                
                let host = url.host?.lowercased() ?? ""
                return matchesPlatform(host: host, platform: currentPlatform)
            }),
               let urlString = platformResult["url"] as? String,
               let resultURL = URL(string: urlString) {
                Log.llm.info("✓ Found content on same platform (\(currentPlatform)): \(resultURL.absoluteString)")
                return resultURL
            }
            
            // Fallback: use first result if no platform match
            if let firstResult = results?.first,
               let urlString = firstResult["url"] as? String,
               let resultURL = URL(string: urlString) {
                Log.llm.info("✓ Found content (different platform): \(resultURL.absoluteString)")
                return resultURL
            }
            
            Log.llm.warning("No valid URL in search results")
            return nil
            
        } catch {
            Log.llm.error("Search failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Build a search query optimized for finding specific content
    private func buildSearchQuery(query: String, context: String) -> String {
        // Don't force site: filters - let Brave find the best match
        // The query should be descriptive enough from the LLM
        return query
    }
    
    /// Detect which platform the user is currently on
    private func detectPlatform(from context: String) -> String {
        let lowerContext = context.lowercased()
        
        if lowerContext.contains("youtube") {
            return "youtube"
        } else if lowerContext.contains("reddit") {
            return "reddit"
        } else if lowerContext.contains("spotify") {
            return "spotify"
        } else if lowerContext.contains("github") {
            return "github"
        } else if lowerContext.contains("twitter") || lowerContext.contains(" x ") {
            return "twitter"
        } else if lowerContext.contains("medium") {
            return "medium"
        } else if lowerContext.contains("dev.to") {
            return "dev.to"
        } else {
            return "web"
        }
    }
    
    /// Check if a host matches the desired platform
    private func matchesPlatform(host: String, platform: String) -> Bool {
        switch platform {
        case "youtube":
            return host.contains("youtube.com") || host.contains("youtu.be")
        case "reddit":
            return host.contains("reddit.com")
        case "spotify":
            return host.contains("spotify.com")
        case "github":
            return host.contains("github.com")
        case "twitter":
            return host.contains("twitter.com") || host.contains("x.com")
        case "medium":
            return host.contains("medium.com")
        case "dev.to":
            return host.contains("dev.to")
        default:
            return true // Accept any for "web"
        }
    }
}
