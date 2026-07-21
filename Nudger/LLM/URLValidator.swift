//
//  URLValidator.swift
//  Nudger
//
//  Created on 2025-10-28.
//

import Foundation
import os.log

/// URL validation to verify links actually exist before showing them
class URLValidator {
    
    /// Validate that a URL actually exists and is accessible
    static func validate(_ url: URL, context: String) async -> Bool {
        // YouTube
        if url.host?.contains("youtube") == true || url.host?.contains("youtu.be") == true {
            guard validateYouTubeURL(url, expectedCreator: nil) else {
                return false
            }
        }
        
        // Spotify
        if url.host?.contains("spotify.com") == true {
            guard validateSpotifyURL(url) else {
                return false
            }
        }
        
        // Basic scheme/host check
        guard let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            return false
        }
        
        guard let host = url.host, !host.isEmpty else {
            return false
        }
        
        // Actually check if URL exists with HEAD request
        return await urlExists(url)
    }
    
    /// Check if a URL actually exists and returns 200-399 status
    private static func urlExists(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3.0
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        // Add User-Agent to avoid anti-scraping blocks
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                Log.llm.debug("URL check: \(url.absoluteString) -> \(statusCode)")
                
                // YouTube often returns 303 for HEAD requests, which is ok
                // 200-299 = success, 300-399 = redirect (also ok for YouTube)
                let isValid = (200...399).contains(statusCode)
                
                if !isValid {
                    Log.llm.warning("URL returned status \(statusCode): \(url.absoluteString)")
                }
                
                return isValid
            }
            
            return false
        } catch {
            Log.llm.warning("URL validation failed for \(url.absoluteString): \(error.localizedDescription)")
            return false
        }
    }
    
    /// Validate that a YouTube URL matches expected creator/channel
    private static func validateYouTubeURL(_ url: URL, expectedCreator: String?) -> Bool {
        guard url.host?.contains("youtube.com") == true || url.host?.contains("youtu.be") == true else {
            return false
        }
        
        let urlString = url.absoluteString
        
        // Allow playlists
        if urlString.contains("playlist?list=") {
            Log.llm.debug("YouTube playlist URL - allowing")
            return true
        }
        
        // Allow channel URLs
        if urlString.contains("/@") || urlString.contains("/channel/") || urlString.contains("/c/") {
            Log.llm.debug("YouTube channel URL - allowing")
            return true
        }
        
        // Extract video ID for video URLs
        guard let videoID = extractYouTubeVideoID(from: url) else {
            Log.llm.warning("Could not extract YouTube video ID from: \(url)")
            return false
        }
        
        // Known bad patterns (rickroll, common meme videos)
        let bannedVideoIDs = [
            "dQw4w9WgXcQ",  // Never Gonna Give You Up
            "oHg5SJYRHA0",  // Rick Astley official
        ]
        
        if bannedVideoIDs.contains(videoID) {
            Log.llm.warning("Blocked known meme video: \(videoID)")
            return false
        }
        
        return true
    }
    
    /// Extract YouTube video ID from various URL formats
    private static func extractYouTubeVideoID(from url: URL) -> String? {
        // Format: youtube.com/watch?v=VIDEO_ID
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let videoID = queryItems.first(where: { $0.name == "v" })?.value {
            return videoID
        }
        
        // Format: youtu.be/VIDEO_ID
        if url.host?.contains("youtu.be") == true {
            return url.pathComponents.last
        }
        
        return nil
    }
    
    /// Validate Spotify URL format
    private static func validateSpotifyURL(_ url: URL) -> Bool {
        guard url.host?.contains("spotify.com") == true else {
            return false
        }
        
        // Basic format check: should have /track/ or /album/ or /artist/
        let path = url.path
        return path.contains("/track/") || path.contains("/album/") || path.contains("/artist/")
    }
}
