import MemoBookCore
import MemoBookDesign
import SwiftUI

/// **Une photo du fil en plein écran** (Hugo, 18/10/2026 : « quand on est dans
/// le chat et qu'on clique sur une photo qu'on a envoyée, elle s'affiche en
/// plein écran »).
///
/// On entre par la photo touchée ; on passe aux autres photos de la même bulle
/// d'un glissé latéral — celles que la bulle cachait sous « +N » comprises. Un
/// pincement ou un double appui zoome, un glissé vers le bas referme quand la
/// photo n'est pas zoomée. Le fond est l'encre de la marque, pas un noir pur :
/// la photo reste le seul objet de l'écran.
///
/// Les images sont relues **à leur taille d'écran** (``ChatModel/fullScreenImage(_:)``),
/// la vignette du fil sert d'attente : on ne voit jamais un écran vide.
struct ChatPhotoViewer: View {
    let viewing: ChatPhotoViewing
    let model: ChatModel
    let onClose: () -> Void

    @State private var selection: Int
    /// Le glissé vers le bas en cours, pour suivre le doigt avant de refermer.
    @State private var dismissOffset: CGFloat = 0
    @State private var isZoomed = false

    init(viewing: ChatPhotoViewing, model: ChatModel, onClose: @escaping () -> Void) {
        self.viewing = viewing
        self.model = model
        self.onClose = onClose
        _selection = State(initialValue: viewing.index)
    }

    var body: some View {
        ZStack(alignment: .top) {
            MemoBookColor.ink
                .opacity(1 - min(0.6, abs(dismissOffset) / 600))
                .ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(viewing.attachments.enumerated()), id: \.element.id) { index, attachment in
                    ZoomablePhoto(attachment: attachment, model: model, isZoomed: $isZoomed)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .offset(y: dismissOffset)
            .simultaneousGesture(dismissGesture)

            header
        }
        .statusBarHidden()
        .onChange(of: selection) { _, _ in isZoomed = false }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MemoBookColor.paper)
                    .frame(width: 44, height: 44)
                    .background(MemoBookColor.ink.opacity(0.4), in: .circle)
            }
            .accessibilityLabel(ChatCopy.PhotoViewer.close)

            Spacer()

            if viewing.attachments.count > 1 {
                Text(ChatCopy.PhotoViewer.position(selection + 1, of: viewing.attachments.count))
                    .font(MemoBookFont.caption)
                    .foregroundStyle(MemoBookColor.paper)
                    .padding(.horizontal, MemoBookSpacing.s)
                    .padding(.vertical, MemoBookSpacing.xs)
                    .background(MemoBookColor.ink.opacity(0.4), in: .capsule)
            }
        }
        .padding(.horizontal, MemoBookSpacing.screenMargin)
        .padding(.top, MemoBookSpacing.xs)
        .opacity(dismissOffset == 0 ? 1 : 0)
    }

    /// Vers le bas, la photo suit le doigt ; lâchée assez loin, elle se referme.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard !isZoomed, abs(value.translation.height) > abs(value.translation.width) else { return }
                dismissOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard !isZoomed else { return }
                if value.translation.height > 140 || value.predictedEndTranslation.height > 320 {
                    onClose()
                } else {
                    withAnimation(.smooth(duration: 0.25)) { dismissOffset = 0 }
                }
            }
    }
}

/// Une photo qui se zoome : pincement de 1× à 4×, double appui pour basculer
/// entre 1× et 2,5×, glissé pour se promener dans la photo zoomée.
private struct ZoomablePhoto: View {
    let attachment: PhotoAttachment
    let model: ChatModel
    @Binding var isZoomed: Bool

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let shown = image ?? attachment.displayUrl.flatMap({ model.image(at: $0) }) {
                    Image(uiImage: shown)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .accessibilityLabel(ChatCopy.PhotoViewer.photo)
                } else {
                    ProgressView()
                        .tint(MemoBookColor.paper)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .contentShape(.rect)
            .gesture(magnify)
            .simultaneousGesture(scale > 1 ? pan : nil)
            .onTapGesture(count: 2) { toggleZoom() }
        }
        .task(id: attachment.displayUrl) {
            guard let url = attachment.displayUrl else { return }
            image = await model.fullScreenImage(url)
        }
        .onChange(of: isZoomed) { _, zoomed in
            // Une autre photo a pris la place : celle-ci repart à 1×.
            if !zoomed, scale != 1 { reset(animated: false) }
        }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(4, max(1, baseScale * value.magnification))
                isZoomed = scale > 1
            }
            .onEnded { _ in
                baseScale = scale
                if scale <= 1.02 { reset(animated: true) }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in baseOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.smooth(duration: 0.25)) {
            if scale > 1 {
                reset(animated: false)
            } else {
                scale = 2.5
                baseScale = 2.5
                isZoomed = true
            }
        }
    }

    private func reset(animated: Bool) {
        let apply = {
            scale = 1
            baseScale = 1
            offset = .zero
            baseOffset = .zero
            isZoomed = false
        }
        if animated { withAnimation(.smooth(duration: 0.25), apply) } else { apply() }
    }
}
