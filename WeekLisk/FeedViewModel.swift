//
//  FeedViewModel.swift
//  WeekLisk
//
//  Created by 魏嘉賢 on 2026/4/26.
//

import Foundation
import SwiftUI

// 1. The exact structure Apple's iTunes API returns
struct ITunesResponse: Codable {
    let results: [ITunesPodcast]
}

struct ITunesPodcast: Codable {
    let trackId: Int
    let collectionName: String? // Podcast Title
    let artistName: String? // Author/Host
    let collectionViewUrl: String? // Link to Apple Podcasts
}

// 2. The ViewModel that fetches the data
@Observable // Use ObservableObject if supporting iOS 16 or older
class FeedViewModel {
    // We reuse your exact FeedItem structure!
    var feedItems: [ContentView.FeedItem] = []
    var isLoading: Bool = false
    var errorMessage: String? = nil
    
    func fetchPodcasts(for goals: [Goal]) async {
            // 1. Get ALL valid goals (filter out empty strings)
            let searchTerms = goals
                .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            // If there are no goals yet, give them a default feed
            let termsToSearch = searchTerms.isEmpty ? ["Productivity"] : searchTerms
            
            await MainActor.run {
                self.isLoading = true
                self.errorMessage = nil
                self.feedItems = [] // Clear the old feed
            }
            
            do {
                // Create a temporary array to hold all the mixed results
                var combinedResults: [ContentView.FeedItem] = []
                
                // 2. Loop through EVERY goal and ask Apple for 3 podcasts per goal
                for term in termsToSearch {
                    guard let encodedTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                          let url = URL(string: "https://itunes.apple.com/search?term=\(encodedTerm)&media=podcast&limit=3")
                    else { continue }
                    
                    print("🌍 Fetching for goal: \(term)")
                    let (data, response) = try await URLSession.shared.data(from: url)
                    
                    // Only process if the server says OK (200)
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        let decodedData = try JSONDecoder().decode(ITunesResponse.self, from: data)
                        
                        let newItems = decodedData.results.compactMap { podcast in
                            ContentView.FeedItem(
                                title: podcast.collectionName ?? "Unknown",
                                // Cool trick: Show the user WHICH goal this is for in the subtitle
                                subtitle: "For your goal: \(term) • By \(podcast.artistName ?? "Unknown")",
                                link: URL(string: podcast.collectionViewUrl ?? "")
                            )
                        }
                        combinedResults.append(contentsOf: newItems)
                    }
                }
                
                // 3. Shuffle the combined array so the feed is a fun mix of all goals!
                combinedResults.shuffle()
                
                // 4. Update the UI exactly once at the end
                await MainActor.run {
                    self.feedItems = combinedResults
                    self.isLoading = false
                }
                
            } catch {
                print("❌ Fetch error: \(error)")
                await MainActor.run {
                    self.errorMessage = "Check your internet connection."
                    self.isLoading = false
                }
            }
        }
}
