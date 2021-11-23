<template>
  <div class="mx-6">
    <b-field label="Set Server Log Level" grouped group-multiline>
      <p class="control"
         v-for="logLevel in logLevels"
         :key="logLevel">
        <b-button @click="setLogLevel(logLevel)"
                  :loading="isLoading"
                  :type="buttonType(logLevel)"
                  :icon-left="buttonIcon(logLevel)">
          {{ logLevel }}
        </b-button>
      </p>
    </b-field>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'ServerLogViewer',
  data() {
    return {
      currentLogLevel: null,
      logLevels: ['DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'],
      isLoading: true,
    };
  },
  async created() {
    try {
      this.isLoading = true;
      this.currentLogLevel = (await CRUDService.serverControl.getLogLevel()).log_level;
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    } finally {
      this.isLoading = false;
    }
  },
  methods: {
    async setLogLevel(logLevel) {
      if (logLevel === this.currentLogLevel) {
        return;
      }
      try {
        this.isLoading = true;
        await CRUDService.serverControl.setLogLevel({ log_level: logLevel });
        this.currentLogLevel = logLevel;
        this.$buefy.toast.open({
          message: `Server Log Level was set to '${logLevel}'!`,
          type: 'is-success',
        });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    buttonType(logLevel) {
      return this.currentLogLevel === logLevel ? 'is-info' : 'is-info is-light';
    },
    buttonIcon(logLevel) {
      return this.currentLogLevel === logLevel ? 'check' : '';
    },
  },
};
</script>
