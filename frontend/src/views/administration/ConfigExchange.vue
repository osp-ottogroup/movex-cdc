<template>
  <div class="mx-6">
    <b-tabs>
      <b-tab-item label="Import">
        <b-field grouped class="file is-primary" :class="{'has-name': !!file}">
          <b-upload v-model="file"
                    class="file-label"
                    :disabled="isLoading"
                    @update:model-value="onImportFileChanged">
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
                    :disabled="isImportDisabled"
                    :loading="isLoading">
            Import
          </b-button>
        </b-field>

        <b-field v-if="importSchemas.length > 1"
                 label="The import file contains more than one schema configuration:"
                 message="Please choose schemas to import.">
          <b-select v-model="selectedImportSchemas"
                    multiple
                    placeholder="Select schema scope"
                    :disabled="isLoading"
                    expanded>
            <option v-for="schemaName in importSchemas" :key="schemaName" :value="schemaName">
              {{ schemaName }}
            </option>
          </b-select>
        </b-field>

        <b-field v-if="importSchemas.length > 1" grouped>
          <b-button size="is-small" :disabled="isLoading" @click="selectAllImportSchemas">Select all</b-button>
          <b-button size="is-small" :disabled="isLoading" @click="clearSelectedImportSchemas">Clear</b-button>
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
      importFileData: null,
      importSchemas: [],
      selectedImportSchemas: [],
    };
  },
  computed: {
    isImportDisabled() {
      return this.file === null
        || this.isLoading
        || this.importFileData === null
        || (this.importSchemas.length > 1 && this.selectedImportSchemas.length === 0);
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
  methods: {
    async onImportFileChanged(file) {
      try {
        if (!file) {
          this.importFileData = null;
          this.importSchemas = [];
          this.selectedImportSchemas = [];
          return;
        }

        const { json, schemaNames } = await this.parseImportFile(file);
        this.importFileData = json;
        this.importSchemas = schemaNames;

        if (schemaNames.length === 1) {
          this.selectedImportSchemas = [schemaNames[0]];
        } else {
          this.selectedImportSchemas = [];
        }
      } catch (e) {
        this.importFileData = null;
        this.importSchemas = [];
        this.selectedImportSchemas = [];
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      }
    },
    async parseImportFile(file) {
      const jsonText = await file.text();
      const json = JSON.parse(jsonText);

      if (!json || typeof json !== 'object' || Array.isArray(json)) {
        throw new Error('Uploaded file must contain a JSON object at root level.');
      }
      if (!Array.isArray(json.schemas)) {
        throw new Error("Uploaded file must contain a 'schemas' array.");
      }
      if (!Array.isArray(json.users)) {
        throw new Error("Uploaded file must contain a 'users' array.");
      }

      const invalidSchema = json.schemas.find(
        (schema) => !schema
          || typeof schema !== 'object'
          || Array.isArray(schema)
          || typeof schema.name !== 'string'
          || schema.name.trim() === '',
      );
      if (invalidSchema) {
        throw new Error("Every entry in 'schemas' must contain a non-empty 'name'.");
      }

      const schemaNames = [...new Set(json.schemas.map((schema) => schema.name.trim()))];
      if (schemaNames.length === 0) {
        throw new Error("Uploaded file must contain at least one schema definition in 'schemas'.");
      }

      return { json, schemaNames };
    },
    selectAllImportSchemas() {
      this.selectedImportSchemas = [...this.importSchemas];
    },
    clearSelectedImportSchemas() {
      this.selectedImportSchemas = [];
    },
    areAllImportSchemasSelected() {
      return this.importSchemas.length > 0
        && this.importSchemas.every((schemaName) => this.selectedImportSchemas.includes(schemaName));
    },
    async onImportClicked() {
      if (this.importFileData === null) {
        return;
      }
      if (this.importSchemas.length > 1 && this.selectedImportSchemas.length === 0) {
        this.$buefy.notification.open({
          message: 'Please choose at least one schema before importing.',
          type: 'is-warning',
          position: 'is-top',
        });
        return;
      }

      const isFullDocumentImport = this.areAllImportSchemasSelected();
      const importScope = isFullDocumentImport
        ? 'the whole document'
        : `${this.selectedImportSchemas.length} selected schema(s)`;
      const warningText = isFullDocumentImport
        ? 'All existing tables and schema rights will be deleted if not contained in this document !!!'
        : 'Only the selected schemas will be imported. Other schemas remain unchanged.';

      this.$buefy.dialog.confirm({
        title: 'Acknowledge import',
        message: `Do you really want to import ${importScope}?<br><br>${warningText}`,
        confirmText: 'Yes',
        cancelText: 'No',
        type: 'is-warning',
        hasIcon: true,
        canCancel: true,
        onConfirm: async () => {
          try {
            this.isLoading = true;
            const importObject = { json_data: this.importFileData };
            if (!isFullDocumentImport) {
              importObject.schema = this.selectedImportSchemas;
            }
            await CRUDService.config.import(importObject);
            this.$buefy.toast.open({
              message: `Import was successful for ${this.selectedImportSchemas.length} schema(s)!`,
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
