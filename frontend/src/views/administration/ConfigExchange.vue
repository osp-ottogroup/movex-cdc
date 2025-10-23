<template>
  <div class="mx-6">
    <b-tabs>
      <b-tab-item label="Import">
        <b-field grouped class="file is-primary" :class="{'has-name': !!file}">
          <b-upload v-model="file"
                    class="file-label"
                    :disabled="isLoading">
            <span class="file-cta">
                <b-icon class="file-icon" icon="upload"></b-icon>
                <span class="file-label">Click to upload</span>
            </span>
            <span class="file-name" v-if="file">
                {{ file.name }}
            </span>
          </b-upload>
          <b-button @click="onImportClicked"
                    type="is-primary"
                    class=""
                    :disabled="file === null || isLoading"
                    :loading="isLoading">
            Import
          </b-button>
        </b-field>
      </b-tab-item>

      <b-tab-item label="Export">
        <b-field>
          <b-select v-model="selectedSchema"
                    placeholder="Select a schema"
                    :loading="isLoading">
            <option value="ALL_SCHEMAS">- All Schemas -</option>
            <option v-for="schema in schemas" :key="schema.id" :value="schema">
              {{ schema.name }}
            </option>
          </b-select>
        </b-field>
        <b-button @click="onExportClicked"
                  type="is-primary"
                  :disabled="selectedSchema === null || isLoading"
                  :loading="isLoading">
          Export
        </b-button>
      </b-tab-item>
    </b-tabs>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';

export default {
  name: 'ConfigExchange',
  data() {
    return {
      isLoading: true,
      schemas: [],
      selectedSchema: null,
      file: null,
    };
  },
  async created() {
    try {
      this.isLoading = true;
      this.schemas = await CRUDService.schemas.getAll();
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
    async onImportClicked() {
      this.$buefy.dialog.confirm({
        title: 'Acknowledge import',
        message: 'Do you really want to import the whole document?<br><br>'
          + 'All existing tables and schema rights will be deleted if not contained in this document !!!',
        confirmText: 'Yes',
        cancelText: 'No',
        type: 'is-warning',
        hasIcon: true,
        canCancel: true,
        onConfirm: async () => {
          try {
            this.isLoading = true;
            const jsonText = await this.file.text();
            const json = JSON.parse(jsonText);
            // TODO: Reduce JSON-File to all or selected schemas + 'users' section
            await CRUDService.config.import({ json_data: json });
            this.$buefy.toast.open({
              message: 'Import was successful!',
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
      });
    },
    async onExportClicked() {
      try {
        this.isLoading = true;
        if (this.selectedSchema === 'ALL_SCHEMAS') {
          const response = await CRUDService.config.export({});
          const fileName = `${this.dateString()}_movex_cdc_export.json`;
          this.downloadJsonFile(response, fileName);
        } else {
          const response = await CRUDService.config.export({ schema: this.selectedSchema.name });
          const fileName = `${this.dateString()}_movex_cdc_export_${this.selectedSchema.name}.json`;
          this.downloadJsonFile(response, fileName);
        }
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
    downloadJsonFile(data, filename) {
      const blob = new Blob([JSON.stringify(data, undefined, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      a.click();
      a.remove();
      // TODO: Show a list of schemas contained in downloaded file + "All Schemas"
    },
    dateString() {
      const date = new Date();
      const year = date.getFullYear();
      const month = date.getMonth() + 1;
      const monthString = month > 9 ? `${month}` : `0${month}`;
      const day = date.getDate();
      const dayString = day > 9 ? `${day}` : `0${day}`;
      const dateString = `${year}-${monthString}-${dayString}`;
      return dateString;
    },
  },
};
</script>

<style lang="scss" scoped>
.file-name {
  max-width: fit-content;
}
</style>
