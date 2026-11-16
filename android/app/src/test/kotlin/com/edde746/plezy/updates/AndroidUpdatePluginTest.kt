package com.edde746.plezy.updates

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AndroidUpdatePluginTest {
  private val installed = ApkIdentity("com.vexilyze.tv", 161L, setOf("release-key"))

  @Test fun acceptsNewerBuildWithSamePackageAndSigningKey() {
    validateUpdateIdentity(installed, installed.copy(versionCode = 162L))
  }

  @Test fun rejectsOtherPackage() {
    val error = assertThrows(UpdateValidationException::class.java) {
      validateUpdateIdentity(installed, installed.copy(packageName = "com.edde746.plezy", versionCode = 162L))
    }
    assertEquals("WRONG_PACKAGE", error.code)
  }

  @Test fun rejectsSameBuildAndDowngrades() {
    for (build in listOf(160L, 161L)) {
      val error = assertThrows(UpdateValidationException::class.java) {
        validateUpdateIdentity(installed, installed.copy(versionCode = build))
      }
      assertEquals("NOT_NEWER", error.code)
    }
  }

  @Test fun rejectsOtherOrMissingSigningKeys() {
    for (signers in listOf(emptySet(), setOf("different-key"), setOf("release-key", "extra-key"))) {
      val error = assertThrows(UpdateValidationException::class.java) {
        validateUpdateIdentity(installed, installed.copy(versionCode = 162L, signers = signers))
      }
      assertEquals("WRONG_SIGNATURE", error.code)
    }
    assertThrows(UpdateValidationException::class.java) {
      validateUpdateIdentity(installed.copy(signers = emptySet()), installed.copy(versionCode = 162L, signers = emptySet()))
    }
  }
}
