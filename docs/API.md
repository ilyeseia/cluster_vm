```markdown
# 📚 التوثيق البرمجي (API)

## الفئات الرئيسية

### 1. TestFramework

فئة لإدارة الاختبارات:

```powershell
class TestFramework {
    [int]$TotalTests
    [int]$PassedTests
    [int]$FailedTests
    [array]$TestResults
    
    [void]RunTest([string]$TestName, [scriptblock]$TestBlock)
    [void]PrintResults()
}

الخصائص:

* TotalTests: إجمالي الاختبارات
* PassedTests: الاختبارات الناجحة
* FailedTests: الاختبارات الفاشلة

الدوال:

* RunTest(): تشغيل اختبار واحد
* PrintResults(): طباعة النتائج
