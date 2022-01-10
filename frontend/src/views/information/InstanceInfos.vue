<template>
  <div class="container">
    <div class="is-flex is-justify-content-flex-end">
      <b-button @click="refresh" icon-left="refresh" size="is-small" type="is-info">Refresh</b-button>
    </div>
    <b-tabs v-model="currentTab" @input="onTabChanged">
      <b-tab-item label="Instance" :value="tabNames.INSTANCE">
        <InstanceDataTable :instanceData="instanceData" :isLoading="isLoading"></InstanceDataTable>
      </b-tab-item>

      <b-tab-item label="Health" :value="tabNames.HEALTH">
        <pre v-html="healthCheck"></pre>
      </b-tab-item>

      <b-tab-item label="Kafka Topics" :value="tabNames.KAFKA_TOPICS">
        <b-field>
          <b-select placeholder="Select a topic" @input="onTopicSelected" :loading="isLoading">
            <option v-for="topic in topics" :key="topic" :value="topic">{{ topic }}</option>
          </b-select>
        </b-field>
        <div>
          <pre v-if="topicDetails">{{ formattedTopicDetails }}</pre>
        </div>
      </b-tab-item>

      <b-tab-item label="Kafka Groups" :value="tabNames.KAFKA_GROUPS">
        <b-field>
          <b-select placeholder="Select a group" @input="onGroupSelected" :loading="isLoading">
            <option v-for="group in groups" :key="group" :value="group">{{ group }}</option>
          </b-select>
        </b-field>
        <div>
          <pre v-if="groupDetails">{{ formattedGroupDetails }}</pre>
        </div>
      </b-tab-item>
    </b-tabs>
  </div>
</template>

<script>
import CRUDService from '@/services/CRUDService';
import { getErrorMessageAsHtml } from '@/helpers';
import InstanceDataTable from '@/views/information/InstanceDataTable.vue';

function escapeHtml(unsafe) {
  return unsafe
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// Convert objects to HTML with collapse for array elements, call recursively
function convertHealthCheckDetailElement(item, indent, inArrayIndent = 0) {
  if (item == null) return 'null';

  const inArrayIndentPrefix = (inArrayIndent === 0 ? '' : '&nbsp;'.repeat(inArrayIndent - 2));

  if (typeof (item) === 'string' || item instanceof String) return `${inArrayIndentPrefix}"${escapeHtml(item)}"`;
  if (typeof (item) === 'number') return `${inArrayIndentPrefix}${item}`;
  if (typeof (item) === 'boolean') return `${inArrayIndentPrefix}${JSON.stringify(item)}`;

  let stringEntries = `${inArrayIndentPrefix}{`;
  Object.entries(item).forEach((entry) => {
    // if item's element is an array then iterate through array and call convertHealthCheckDetailElement for each element
    if (Array.isArray(entry[1])) {
      stringEntries += `<details><summary>${'&nbsp;'.repeat(indent - 2)}${escapeHtml(entry[0])} (${entry[1].length}) [</summary>`;
      stringEntries += entry[1].map((x) => convertHealthCheckDetailElement(x, indent + 4, indent + 4)).join(',<br/>');
      stringEntries += '</details>';
      stringEntries += `${'&nbsp;'.repeat(indent)}]`;
    } else {
      // if item's element is other than array then call convertHealthCheckDetailElement for each element
      stringEntries += `<br/>${'&nbsp;'.repeat(indent)}${escapeHtml(entry[0])}: `;
      stringEntries += `${convertHealthCheckDetailElement(entry[1], indent + 2)}`;
    }
  });
  stringEntries += `<br/>${'&nbsp;'.repeat(indent - 2)}}`;
  return stringEntries;
}

async function readAndConvertHealthCheck() {
  const rawHealthCheck = (await CRUDService.healthCheck.check());
  return convertHealthCheckDetailElement(rawHealthCheck, 2);
}

export default {
  name: 'InstanceInfos',
  components: { InstanceDataTable },
  data() {
    return {
      tabNames: {
        INSTANCE: 'INSTANCE',
        HEALTH: 'HEALTH',
        KAFKA_TOPICS: 'KAFKA_TOPICS',
        KAFKA_GROUPS: 'KAFKA_GROUPS',
      },
      currentTab: 'INSTANCE',
      instanceData: [],
      healthCheck: '',
      topics: [],
      selectedTopic: null,
      groups: [],
      selectedGroup: null,
      topicDetails: null,
      groupDetails: null,
      isLoading: true,
    };
  },
  async created() {
    try {
      // load only the data of the first tab (which is instance information)
      await this.loadInstanceData();
    } catch (e) {
      this.$buefy.notification.open({
        message: getErrorMessageAsHtml(e, 'An error occurred while loading instance infos!'),
        type: 'is-danger',
        indefinite: true,
        position: 'is-top',
      });
    } finally {
      this.isLoading = false;
    }
  },
  computed: {
    formattedTopicDetails() {
      return JSON.stringify(this.topicDetails, null, 4);
    },
    formattedGroupDetails() {
      return JSON.stringify(this.groupDetails, null, 4);
    },
  },
  methods: {
    async onTopicSelected(topic) {
      try {
        this.isLoading = true;
        this.selectedTopic = topic;
        this.topicDetails = null;
        this.topicDetails = await CRUDService.kafka.topics.get({ topic });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading topic details!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async onGroupSelected(group) {
      try {
        this.isLoading = true;
        this.selectedGroup = group;
        this.groupDetails = null;
        this.groupDetails = await CRUDService.kafka.groups.get({ group_id: group });
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading group details!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
    async loadHealthData() {
      // this.healthCheck = (await CRUDService.healthCheck.check());
      this.healthCheck = (await readAndConvertHealthCheck());
    },
    async loadInstanceData() {
      this.instanceData = (await CRUDService.instance.info()).config_info;
    },
    async loadKafkaTopicsData() {
      this.topics = (await CRUDService.kafka.topics.getAll()).topics;
    },
    async loadKafkaGroupsData() {
      this.groups = (await CRUDService.kafka.groups.getAll()).groups;
    },
    onTabChanged(value) {
      this.loadTab(value);
    },
    refresh() {
      this.loadTab(this.currentTab);
    },
    async loadTab(tabName) {
      try {
        this.isLoading = true;
        switch (tabName) {
          case this.tabNames.HEALTH:
            await this.loadHealthData();
            break;
          case this.tabNames.INSTANCE:
            await this.loadInstanceData();
            break;
          case this.tabNames.KAFKA_TOPICS:
            await this.loadKafkaTopicsData();
            if (this.selectedTopic) {
              await this.onTopicSelected(this.selectedTopic);
            }
            break;
          case this.tabNames.KAFKA_GROUPS:
            await this.loadKafkaGroupsData();
            if (this.selectedGroup) {
              await this.onGroupSelected(this.selectedGroup);
            }
            break;
          default:
            throw new Error(`tab value ${tabName} is unknown`);
        }
      } catch (e) {
        this.$buefy.notification.open({
          message: getErrorMessageAsHtml(e, 'An error occurred while loading tab data!'),
          type: 'is-danger',
          indefinite: true,
          position: 'is-top',
        });
      } finally {
        this.isLoading = false;
      }
    },
  },
};

</script>
