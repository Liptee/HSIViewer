import SwiftUI

struct GlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder var content: Content
    
    init(
        cornerRadius: CGFloat = 12,
        padding: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        
        Group {
            if padding > 0 {
                content.padding(padding)
            } else {
                content
            }
        }
        .modifier(GlassOrFallback(shape: shape))
    }
}

struct GlassCapsule<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder var content: Content
    
    init(padding: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        Group {
            if padding > 0 {
                content.padding(padding)
            } else {
                content
            }
        }
        .modifier(GlassOrFallback(shape: Capsule()))
    }
}

private struct GlassOrFallback<S: InsettableShape>: ViewModifier {
    let shape: S
    
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

struct GlassBackground: ViewModifier {
    let cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        
        if #available(macOS 26.0, *) {
            content
                .background {
                    Rectangle()
                        .fill(.clear)
                        .glassEffect(in: shape)
                }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

extension View {
    func glassBackground(cornerRadius: CGFloat = 12) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
    
    @ViewBuilder
    func conditionalGlassContainer<V: View>(@ViewBuilder content: () -> V) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                content()
            }
        } else {
            content()
        }
    }
}

struct GlassEffectContainerWrapper<Content: View>: View {
    @ViewBuilder var content: Content
    
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
        }
    }
}

