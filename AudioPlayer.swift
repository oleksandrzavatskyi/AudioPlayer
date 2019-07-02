//
//  AudioPlayer.swift
//
//  Created by Oleksandr Zavatskyi on 19.12.2018.
//  Copyright © 2018 PettersonApps. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer

class AudioPlayer {
    
    //MARK: - Public Properties
    
    static var player = AudioPlayer()
    
    var lastPlayerState: SPTPlaybackState?
    
    var playlist: Playlist! {
        willSet {
            if playlist != nil {
                if playlist.backendID != newValue.backendID {
                    isRepeatSelected = false
                    isShuffleSelected = false
                }
            }
        }
        didSet {
            tracklist = playlist.tracks
        }
    }
    
    var tracklist: [Track] = []
    
    var track: Track!
    
    var playTimer: Timer?
    
    var currentTrackElapsedTime: TimeInterval = 0
    
    var isRepeatSelected: Bool = false {
        didSet {
            if isRepeatSelected {
                SPTAudioStreamingController.sharedInstance().setRepeat(.one) { error in
                    if let error = error {
                        print(error.localizedDescription)
                    }
                }
            } else {
                SPTAudioStreamingController.sharedInstance().setRepeat(.off) { error in
                    if let error = error {
                        print(error.localizedDescription)
                    }
                }
            }
        }
    }
    
    var isShuffleSelected: Bool = false {
        didSet {
            if isShuffleSelected {
                configureShuffledTracklist()
            } else {
                tracklist = playlist.tracks
            }
        }
    }
    
    //MARK: - Actions
    
    @objc fileprivate func updateTime() {
        if let track = AudioPlayer.player.track {
            AudioPlayer.player.fetchPlayerState()
            if AudioPlayer.player.currentTrackElapsedTime < track.duration - Constants.playTimerInterval {
                print("\(AudioPlayer.player.currentTrackElapsedTime)   ---   \(track.duration)")
                AudioPlayer.player.currentTrackElapsedTime += TimeInterval(Constants.playTimerInterval)
                SpotifyManager.shared.updateNowPlayingInfoCenterWithoutArtwork()
                NotificationCenter.default.post(name: Constants.playerTimeNotification, object: nil)
            } else {
                AudioPlayer.player.playNextTrackWithConditions()
            }
        }
    }
    
    //MARK: - Private
    
    fileprivate func playNextTrackWithConditions() {
        if isRepeatSelected {
            AudioPlayer.player.playTrack()
        } else {
            playNextTrack()
        }
    }
    
    fileprivate func configureShuffledTracklist() {
        var tracks = playlist.tracks.shuffled()
        tracks.removeAll(where: { $0 == AudioPlayer.player.track })
        var shuffledTracks: [Track] = [track]
        shuffledTracks.append(contentsOf: tracks)
        tracklist = shuffledTracks
    }
    
    //MARK: - Public
    
    func activateTimer() {
        if playTimer == nil {
            playTimer = Timer.scheduledTimer(timeInterval: Constants.playTimerInterval, target: self, selector: #selector(updateTime), userInfo: nil, repeats: true)
        }
    }
    
    func deactivateTimer() {
        AudioPlayer.player.playTimer?.invalidate()
        AudioPlayer.player.playTimer = nil
    }
    

    func update(playerState: SPTPlaybackState) {
        lastPlayerState = playerState

        if let _ = AudioPlayer.player.playTimer {
            PlayerView.sharedInstance.changePausePlayButtonState()
        }
    }
    
    func fetchPlayerState() {
        update(playerState: SPTAudioStreamingController.sharedInstance().playbackState)
    }
    
    func didTapPauseOrPlay() {
        if let lastPlayerState = lastPlayerState {
            if lastPlayerState.isPlaying {
                AudioPlayer.player.pause()
            } else {
                AudioPlayer.player.resume()
            }
        } else {
            if SPTAudioStreamingController.sharedInstance().playbackState.isPlaying {
                AudioPlayer.player.pause()
            } else {
                AudioPlayer.player.resume()
            }
        }
    }
    
    func playTrack(completionHandler: (()->())? = nil) {
        AudioPlayer.player.deactivateTimer()
        AudioPlayer.player.currentTrackElapsedTime = 0
        try? SPTAudioStreamingController.sharedInstance().start(withClientId: SpotifyManager.shared.authManager.clientID ?? "")
        if SpotifyManager.shared.authManager.session?.isValid() == true {
            SPTAudioStreamingController.sharedInstance().playSpotifyURI(track.uri,
                                                                        startingWith: 0,
                                                                        startingWithPosition: 0)
            { (error) in
                if let error = error {
                    print("\(error.localizedDescription)")
                } else {
                    AudioPlayer.player.activateTimer()
                    AudioPlayer.player.resume()
                    completionHandler?()
                }
            }
        } else {
            AudioPlayer.player.currentTrackElapsedTime = 0
            SPTAudioStreamingController.sharedInstance().playSpotifyURI(track.uri,
                                                                        startingWith: 0,
                                                                        startingWithPosition: 0)
            { (error) in
                if let error = error {
                    print("\(error.localizedDescription)")
                } else {
                    AudioPlayer.player.currentTrackElapsedTime = 0
                    AudioPlayer.player.activateTimer()
                    AudioPlayer.player.resume()
                    completionHandler?()
                }
            }
        }
    }
    
    func resume() {
        AudioPlayer.player.activateTimer()
        
        if !PlayerView.sharedInstance.isPresented &&
            !(UIApplication.shared.topMostViewController() is PlayerViewController)  {
            PlayerView.sharedInstance.showPlayerView()
        }
        
        SPTAudioStreamingController.sharedInstance().setIsPlaying(true,
                                                                  callback: { _ in
            SpotifyManager.shared.updateNowPlayingInfoCenter()
            MPNowPlayingInfoCenter.default().playbackState = .playing
        })
    }
    
    func pause() {
        AudioPlayer.player.deactivateTimer()
        SPTAudioStreamingController.sharedInstance().setIsPlaying(false,
                                                                  callback: { _ in
            SpotifyManager.shared.updateNowPlayingInfoCenter()
            PlayerView.sharedInstance.changePausePlayButtonState(to: true)
            MPNowPlayingInfoCenter.default().playbackState = .paused
        })
    }
    
    func seek(to position: TimeInterval, completionHandler: SPTErrorableOperationCallback? = nil) {
        SPTAudioStreamingController.sharedInstance().seek(to: position,
                                                          callback: completionHandler ?? { _ in
                                                            SpotifyManager.shared.updateNowPlayingInfoCenter()
            })
    }
    
    func playNextTrack() {
        if let index = AudioPlayer.player.tracklist.firstIndex(of: AudioPlayer.player.track) {
            if index < AudioPlayer.player.tracklist.endIndex - 1 {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                let tracks = AudioPlayer.player.tracklist
                let nextTrack = tracks[tracks.index(after: index)]
                AudioPlayer.player.track = nextTrack
                AudioPlayer.player.playTrack()
                NotificationCenter.default.post(name: Constants.nextTrackNotification, object: nil)
            } else {
                pause()
                if let controller = UIApplication.shared.topMostViewController() as? PlayerViewController {
                    controller.playPauseButton.isSelected = true
                }
            }
        } else {
            guard let newTrack = AudioPlayer.player.tracklist.first else {
                pause()
                if let controller = UIApplication.shared.topMostViewController() as? PlayerViewController {
                    controller.playPauseButton.isSelected = true
                }
                return
            }
            AudioPlayer.player.track = newTrack
            AudioPlayer.player.playTrack()
            NotificationCenter.default.post(name: Constants.nextTrackNotification, object: nil)
        }
    }
    
    func playPreviousTrack() {
        if let index = AudioPlayer.player.tracklist.firstIndex(of: AudioPlayer.player.track) {
            if index > 0 {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                let tracks = AudioPlayer.player.tracklist
                let previousTrack = tracks[tracks.index(before: index)]
                AudioPlayer.player.track = previousTrack
                AudioPlayer.player.playTrack()
            } else {
                pause()
            }
        } else {
            guard let newTrack = AudioPlayer.player.tracklist.first else {
                pause()
                if let controller = UIApplication.shared.topMostViewController() as? PlayerViewController {
                    controller.playPauseButton.isSelected = true
                }
                return
            }
            AudioPlayer.player.track = newTrack
            AudioPlayer.player.playTrack()
            NotificationCenter.default.post(name: Constants.nextTrackNotification, object: nil)
        }
    }
}
