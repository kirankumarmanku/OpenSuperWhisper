//
//  BridgeiOS.h
//  OpenSuperWhisperiOS
//
//  The iOS target's bridging header: whisper.cpp from whisper.xcframework only. The macOS
//  Bridge.h also pulls in the Rust autocorrect library, which is not built for iOS.
//

#include <whisper/whisper.h>
