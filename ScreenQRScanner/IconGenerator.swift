//
//  IconGenerator.swift
//  ScreenQRScanner
//
//  Created by haojieli on 2025/12/29.
//

import SwiftUI

struct AppIconView: View {
    var body: some View {
        ZStack {
            // 背景
            LinearGradient(gradient: Gradient(colors: [Color.blue, Color.purple]), startPoint: .topLeading, endPoint: .bottomTrailing)
            
            // 图标主体
            Image(systemName: "qrcode.viewfinder")
                .resizable()
                .scaledToFit()
                .foregroundColor(.white)
                .padding(180) // 调整内边距
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .frame(width: 1024, height: 1024) // App Icon 标准尺寸
        .ignoresSafeArea()
    }
}

struct AppIconView_Previews: PreviewProvider {
    static var previews: some View {
        AppIconView()
            .previewLayout(.sizeThatFits)
    }
}
