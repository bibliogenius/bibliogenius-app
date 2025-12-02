import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/services/wizard_service.dart';

void main() {
  test('WizardService checks and sets seen status', () async {
    SharedPreferences.setMockInitialValues({});
    
    expect(await WizardService.hasSeenDashboardWizard(), false);
    
    await WizardService.markDashboardWizardSeen();
    
    expect(await WizardService.hasSeenDashboardWizard(), true);
    
    await WizardService.resetWizard();
    
    expect(await WizardService.hasSeenDashboardWizard(), false);
  });
}
