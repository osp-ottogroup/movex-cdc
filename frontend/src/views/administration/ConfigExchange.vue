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

        <div v-if="importSchemas.length > 0" class="mt-4">
          <b-message v-if="importSchemas.length > 1" type="is-info">
            The uploaded file contains {{ importSchemas.length }} schemas. Select one or more schemas to import.
          </b-message>

          <b-field v-if="importSchemas.length > 1" label="Schemas to import">
            <b-select v-model="selectedSchemaNames"
                      multiple
                      expanded
                      :disabled="isLoading">
              <option v-for="schema in importSchemas" :key="schema.name" :value="schema.name">
                {{ schema.name }}
              </option>
            </b-select>
          </b-field>

          <b-field v-if="importSchemas.length > 1 && areAllImportSchemasSelected">
            <b-checkbox v-model="deactivateMissingSchemas" :disabled="isLoading">
              Deactivate schemas that are not contained in the import set.
            </b-checkbox>
          </b-field>
        </div>
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
      importData: null,
      selectedSchemaNames: [],
      deactivateMissingSchemas: false,
    };
  },
  computed: {
    importSchemas() {
      return this.importData?.schemas ?? [];
    },
    areAllImportSchemasSelected() {
      return this.importSchemas.length > 0
        && this.selectedSchemaNames.length === this.importSchemas.length;
    },
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
  watch: {
    async file(newFile) {
      await this.loadImportData(newFile);
    },
    selectedSchemaNames() {
      if (!this.areAllImportSchemasSelected) {
        this.deactivateMissingSchemas = false;
      }
    },
  },
  methods: {
    async loadImportData(file) {
      if (!file) {
        this.importData = null;
        this.selectedSchemaNames = [];
        this.deactivateMissingSchemas = false;
        return;
      }

      try {
        const jsonText = await file.text();
        const jsonData = JSON.parse(jsonText);

        if (!Array.isArray(jsonData.schemas)) {
          throw new Error("Import file should contain a 'schemas' array.");
        }

        if (!Array.isArray(jsonData.users)) {
          throw new Error("Import file should contain a 'users' array.");
        }

        this.importData = jsonData;
        this.selectedSchemaNames = jsonData.schemas.map((schema) => schema.name);
        this.deactivateMissingSchemas = false;
      } catch (e) {
        this.importData = null;
        this.selectedSchemaNames = [];
        this.deactivateMissingSchemas = false;
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
        this.file = null;
      }
    },
    getSelectedSchemaNames() {
      return this.selectedSchemaNames.length > 0 ? this.selectedSchemaNames : this.importSchemas.map((schema) => schema.name);
    },
    async onImportClicked() {
      if (!this.importData) {
        return;
      }

      const selectedSchemaNames = this.getSelectedSchemaNames();
      const selectedSchemaLabel = selectedSchemaNames.length === 1
        ? `schema '${selectedSchemaNames[0]}'`
        : `${selectedSchemaNames.length} schemas`;
      const cleanupMessage = this.deactivateMissingSchemas
        ? 'Schemas not contained in the selected import set will be deactivated.'
        : 'Schemas not contained in the selected import set will remain unchanged.';

      this.$buefy.dialog.confirm({
        title: 'Acknowledge import',
        message: `Do you really want to import ${selectedSchemaLabel}?<br><br>`
          + `${cleanupMessage}<br>`
          + 'All existing tables and schema rights will be updated according to the imported schema data.',
        confirmText: 'Yes',
        cancelText: 'No',
        type: 'is-warning',
        hasIcon: true,
        canCancel: true,
        onConfirm: async () => {
          try {
            this.isLoading = true;
            await CRUDService.config.import({
              json_data: this.importData,
              schema: this.getSelectedSchemaNames(),
              deactivate_missing_schemas: this.deactivateMissingSchemas,
            });
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
