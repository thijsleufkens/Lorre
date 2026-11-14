import SwiftUI

/// The first-run sheet: what Lorre does, your name, and what macOS will ask for.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    private let strings = Strings.current

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.x6) {
            Text(strings.onboardingStepCounter(model.stepNumber, of: OnboardingModel.stepCount).uppercased())
                .font(DS.FontStyle.kicker)
                .foregroundStyle(DS.ColorToken.fgSecondary)
            stepContent
            Spacer(minLength: 0)
            buttons
        }
        .padding(DS.Space.x8)
        .frame(width: DS.Layout.reviewListWidth, height: DS.Layout.reviewListWidth)
        .background(DS.ColorToken.bgApp)
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .welcome:
            VStack(alignment: .leading, spacing: DS.Space.x4) {
                title(strings.onboardingWelcomeTitle)
                paragraph(strings.onboardingWelcomeBody)
            }
        case .name:
            VStack(alignment: .leading, spacing: DS.Space.x4) {
                title(strings.onboardingNameTitle)
                TextField(strings.onboardingNameField, text: $model.name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.next() }
                    .accessibilityLabel(strings.onboardingNameField)
                    .help(strings.onboardingNameBody)
                paragraph(strings.onboardingNameBody)
            }
        case .permissions:
            VStack(alignment: .leading, spacing: DS.Space.x4) {
                title(strings.onboardingPermissionsTitle)
                paragraph(strings.onboardingPermissionsAsk)
                paragraph(strings.onboardingPermissionsWhy)
                paragraph(strings.onboardingPermissionsAgain)
            }
        }
    }

    private var buttons: some View {
        HStack {
            if !model.isFirstStep {
                Button(strings.back) { model.back() }
                    .buttonStyle(SecondaryControlButtonStyle())
                    .help(strings.onboardingBackHelp)
            }
            Spacer()
            if model.isLastStep {
                Button(strings.onboardingStart) { model.complete() }
                    .buttonStyle(PrimaryControlButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .help(strings.onboardingStartHelp)
            } else {
                Button(strings.onboardingNext) { model.next() }
                    .buttonStyle(PrimaryControlButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canContinue)
                    .help(strings.onboardingNextHelp)
            }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(DS.FontStyle.appTitle)
            .foregroundStyle(DS.ColorToken.fgPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(DS.FontStyle.outcomeText)
            .foregroundStyle(DS.ColorToken.fgSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
